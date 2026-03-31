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

  def run_runtime(:python, code) do
    invoke(runtime(:python), ["-c", code])
  end

  def run_runtime(:lua, code) do
    invoke(runtime(:lua), ["-e", code])
  end

  def run_runtime(:common_lisp, code) do
    case runtime(:common_lisp) do
      %{available: true, engine: "sbcl"} = runtime ->
        invoke(runtime, ["--non-interactive", "--eval", code])

      %{available: true, engine: "clisp"} = runtime ->
        invoke(runtime, ["-q", "-x", code])

      _ ->
        {:error, "Common Lisp runtime is unavailable"}
    end
  end

  def run_runtime(:zig, _code) do
    {:error, "Zig runtime execution is not supported through the host adapter"}
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

  defp invoke(%{available: true, engine: engine}, args) do
    case External.run(engine, args) do
      {:ok, output} -> {:ok, output}
      {:error, %{output: output}} -> {:error, output}
    end
  end

  defp invoke(_runtime, _args), do: {:error, "runtime unavailable"}

  defp read_uname do
    case External.run("uname", ["-srm"]) do
      {:ok, output} -> output
      _ -> "unknown"
    end
  end
end
