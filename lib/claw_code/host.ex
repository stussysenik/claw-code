defmodule ClawCode.Host do
  alias ClawCode.Adapters.External

  def kernel_facts do
    %{
      cwd: File.cwd!(),
      shell: System.get_env("SHELL") || "unknown",
      uname: read_uname(),
      elixir: System.version(),
      otp: :erlang.system_info(:otp_release)
    }
  end

  def runtime_matrix do
    [
      detect(:python, "Python", ["python3"]),
      detect(:lua, "Lua", ["luajit", "lua"]),
      detect(:common_lisp, "Common Lisp", ["sbcl", "clisp"]),
      detect(:zig, "Zig", ["zig"])
    ]
  end

  def runtime(id) do
    Enum.find(runtime_matrix(), &(&1.id == id))
  end

  def run_runtime(runtime_id, code, opts \\ []) do
    case run_runtime_with_receipt(runtime_id, code, opts) do
      {:ok, output, _receipt} -> {:ok, output}
      {:error, output, _receipt} -> {:error, output}
    end
  end

  def run_runtime_with_receipt(runtime_id, code, opts \\ [])

  def run_runtime_with_receipt(:python, code, opts) do
    invoke(runtime(:python), ["-c", code], opts)
  end

  def run_runtime_with_receipt(:lua, code, opts) do
    invoke(runtime(:lua), ["-e", code], opts)
  end

  def run_runtime_with_receipt(:common_lisp, code, opts) do
    case runtime(:common_lisp) do
      %{available: true, engine: "sbcl"} = runtime ->
        invoke(runtime, ["--non-interactive", "--eval", code], opts)

      %{available: true, engine: "clisp"} = runtime ->
        invoke(runtime, ["-q", "-x", code], opts)

      _ ->
        {:error, "Common Lisp runtime is unavailable", unavailable_receipt(:common_lisp)}
    end
  end

  def run_runtime_with_receipt(:zig, _code, _opts) do
    {:error, "Zig runtime execution is not supported through the host adapter",
     unavailable_receipt(:zig)}
  end

  defp detect(id, label, binaries) do
    case Enum.find_value(binaries, &System.find_executable/1) do
      nil ->
        %{id: id, label: label, available: false, engine: "missing", binary: nil}

      binary_path ->
        engine = Path.basename(binary_path)
        %{id: id, label: label, available: true, engine: engine, binary: binary_path}
    end
  end

  defp invoke(%{available: true, binary: binary} = runtime, args, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms)

    external_opts =
      if is_nil(timeout_ms) do
        []
      else
        [timeout_ms: timeout_ms]
      end

    case External.run_with_receipt(binary, args, external_opts) do
      {:ok, output, receipt} -> {:ok, output, annotate_receipt(receipt, runtime, args)}
      {:error, receipt} -> {:error, receipt.output, annotate_receipt(receipt, runtime, args)}
    end
  end

  defp invoke(%{id: runtime_id}, _args, _opts),
    do: {:error, "runtime unavailable", unavailable_receipt(runtime_id)}

  defp read_uname do
    case External.run("uname", ["-srm"]) do
      {:ok, output} -> output
      _ -> "unknown"
    end
  end

  defp unavailable_receipt(runtime_id) do
    %{
      command: Atom.to_string(runtime_id),
      cwd: File.cwd!(),
      env_keys: [],
      started_at: nil,
      duration_ms: 0,
      runtime: Atom.to_string(runtime_id),
      engine: "missing",
      invocation: Atom.to_string(runtime_id),
      status: "unavailable",
      exit_status: "unavailable",
      output: "runtime unavailable"
    }
  end

  defp annotate_receipt(receipt, runtime, args) do
    Map.merge(receipt, %{
      runtime: Atom.to_string(runtime.id),
      engine: runtime.engine,
      invocation: Enum.join([Path.basename(runtime.binary) | Enum.map(args, &to_string/1)], " ")
    })
  end
end
