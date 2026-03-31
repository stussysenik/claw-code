defmodule ClawCode.Adapters.External do
  @default_timeout_ms 5_000

  def run(command, args, opts \\ []) do
    case run_with_receipt(command, args, opts) do
      {:ok, output, _receipt} ->
        {:ok, output}

      {:error, receipt} ->
        {:error, %{status: receipt.exit_status, output: receipt.output}}
    end
  end

  def run_with_receipt(command, args, opts \\ []) do
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd, File.cwd!())
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    started_at = System.monotonic_time(:millisecond)
    started_iso = utc_now()

    case resolve_executable(command) do
      nil ->
        {:error,
         receipt(
           command,
           cd,
           env,
           started_at,
           started_iso,
           "spawn_failed",
           "command not found: #{command}"
         )}

      executable ->
        try do
          port =
            Port.open(
              {:spawn_executable, String.to_charlist(executable)},
              [
                :binary,
                :exit_status,
                :use_stdio,
                :stderr_to_stdout,
                {:args, Enum.map(args, &to_string/1)},
                {:cd, String.to_charlist(cd)},
                {:env,
                 Enum.map(env, fn {key, value} -> {to_charlist(key), to_charlist(value)} end)}
              ]
            )

          await_port(port, executable, cd, env, started_at, started_iso, timeout_ms, [])
        rescue
          error in [ArgumentError, ErlangError] ->
            {:error,
             receipt(
               command,
               cd,
               env,
               started_at,
               started_iso,
               "spawn_failed",
               Exception.message(error)
             )}
        end
    end
  end

  defp await_port(port, command, cd, env, started_at, started_iso, timeout_ms, chunks) do
    receive do
      {^port, {:data, data}} ->
        await_port(port, command, cd, env, started_at, started_iso, timeout_ms, [data | chunks])

      {^port, {:exit_status, status}} ->
        output = chunks |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim()

        receipt = receipt(command, cd, env, started_at, started_iso, status, output)

        if status == 0 do
          {:ok, output, receipt}
        else
          {:error, receipt}
        end
    after
      timeout_ms ->
        Port.close(port)

        {:error,
         receipt(
           command,
           cd,
           env,
           started_at,
           started_iso,
           "timeout",
           "timed out after #{timeout_ms}ms"
         )}
    end
  end

  defp resolve_executable(command) do
    cond do
      Path.type(command) == :absolute and File.exists?(command) ->
        command

      true ->
        System.find_executable(command)
    end
  end

  defp receipt(command, cd, env, started_at, started_iso, exit_status, output) do
    %{
      command: command,
      cwd: cd,
      env_keys: env |> Enum.map(fn {key, _value} -> key end) |> Enum.uniq() |> Enum.sort(),
      started_at: started_iso,
      duration_ms: System.monotonic_time(:millisecond) - started_at,
      status: status(exit_status),
      exit_status: exit_status,
      output: String.trim(output)
    }
  end

  defp status(0), do: "ok"
  defp status(value) when is_integer(value), do: "error"
  defp status("timeout"), do: "timeout"
  defp status("spawn_failed"), do: "spawn_failed"

  defp utc_now do
    DateTime.utc_now()
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
