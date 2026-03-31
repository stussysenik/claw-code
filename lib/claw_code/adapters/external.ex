defmodule ClawCode.Adapters.External do
  def run(command, args, opts \\ []) do
    env = Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd, File.cwd!())

    case System.cmd(command, args, env: env, cd: cd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, %{status: status, output: String.trim(output)}}
    end
  rescue
    error in ErlangError ->
      {:error, %{status: :spawn_failed, output: Exception.message(error)}}
  end
end
