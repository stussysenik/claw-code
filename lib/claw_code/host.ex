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

  def run_runtime(runtime_id, code) do
    case run_runtime_with_receipt(runtime_id, code) do
      {:ok, output, _receipt} -> {:ok, output}
      {:error, output, _receipt} -> {:error, output}
    end
  end

  def run_runtime_with_receipt(:python, code) do
    invoke(runtime(:python), ["-c", code])
  end

  def run_runtime_with_receipt(:lua, code) do
    invoke(runtime(:lua), ["-e", code])
  end

  def run_runtime_with_receipt(:common_lisp, code) do
    case runtime(:common_lisp) do
      %{available: true, engine: "sbcl"} = runtime ->
        invoke(runtime, ["--non-interactive", "--eval", code])

      %{available: true, engine: "clisp"} = runtime ->
        invoke(runtime, ["-q", "-x", code])

      _ ->
        {:error, "Common Lisp runtime is unavailable", unavailable_receipt(:common_lisp)}
    end
  end

  def run_runtime_with_receipt(:zig, _code) do
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

  defp invoke(%{available: true, binary: binary}, args) do
    case External.run_with_receipt(binary, args) do
      {:ok, output, receipt} -> {:ok, output, receipt}
      {:error, receipt} -> {:error, receipt.output, receipt}
    end
  end

  defp invoke(%{id: runtime_id}, _args),
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
      status: "unavailable",
      exit_status: "unavailable",
      output: "runtime unavailable"
    }
  end
end
