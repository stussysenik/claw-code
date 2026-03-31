defmodule ClawCode.NativeRanker do
  alias ClawCode.Entry

  @source_path Path.expand("../../native/token_ranker.zig", __DIR__)
  @binary_path Path.expand("../../priv/native/token_ranker", __DIR__)

  def available? do
    not is_nil(System.find_executable("zig")) and File.exists?(@source_path)
  end

  def build do
    ensure_compiled!()
    @binary_path
  end

  def rank(prompt, entries) do
    case safe_rank(prompt, entries) do
      {:ok, ranked} -> ranked
      {:error, reason} -> raise "native ranker failed: #{format_error(reason)}"
    end
  end

  def safe_rank(prompt, entries, opts \\ []) do
    ensure_compiled = Keyword.get(opts, :ensure_compiled, &ensure_compiled/0)
    runner = Keyword.get(opts, :runner, &run_binary/1)

    input =
      [
        "prompt\t#{sanitize(prompt)}\n",
        Enum.map(entries, fn %Entry{} = entry ->
          [
            "entry\t",
            Atom.to_string(entry.kind),
            "\t",
            sanitize(entry.name),
            "\t",
            sanitize(entry.source_hint),
            "\t",
            sanitize(entry.responsibility),
            "\n"
          ]
        end)
      ]
      |> IO.iodata_to_binary()

    tmp_path = temp_input_path()
    File.write!(tmp_path, input)

    with :ok <- ensure_compiled.(),
         {output, 0} <- runner.(tmp_path),
         {:ok, ranked} <- parse_output(output) do
      {:ok, ranked}
    else
      {:error, _reason} = error ->
        error

      {output, status} ->
        {:error, {:execution_failed, status, String.trim(output)}}
    end
  after
    if tmp_path = Process.get({__MODULE__, :tmp_path}) do
      File.rm(tmp_path)
      Process.delete({__MODULE__, :tmp_path})
    end
  end

  defp ensure_compiled do
    needs_compile? =
      not File.exists?(@binary_path) or
        File.stat!(@source_path).mtime > File.stat!(@binary_path).mtime

    if needs_compile? do
      File.mkdir_p!(Path.dirname(@binary_path))

      case System.cmd(
             "zig",
             [
               "build-exe",
               @source_path,
               "-O",
               "ReleaseFast",
               "-femit-bin=#{@binary_path}"
             ],
             stderr_to_stdout: true
           ) do
        {_output, 0} -> :ok
        {output, status} -> {:error, {:compile_failed, status, String.trim(output)}}
      end
    else
      :ok
    end
  end

  defp ensure_compiled! do
    case ensure_compiled() do
      :ok -> :ok
      {:error, reason} -> raise "failed to compile Zig ranker: #{format_error(reason)}"
    end
  end

  defp run_binary(tmp_path) do
    System.cmd(@binary_path, [tmp_path], stderr_to_stdout: true)
  end

  defp parse_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, rows} ->
      case String.split(line, "\t", parts: 4) do
        [kind, name, source_hint, score] ->
          row = %{
            kind: String.to_existing_atom(kind),
            name: name,
            source_hint: source_hint,
            score: String.to_integer(score)
          }

          {:cont, {:ok, [row | rows]}}

        _ ->
          {:halt, {:error, {:invalid_output, line}}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sanitize(value) do
    value
    |> String.replace("\t", " ")
    |> String.replace("\n", " ")
    |> String.trim()
  end

  defp temp_input_path do
    path = Path.join(System.tmp_dir!(), "claw-ranker-#{System.unique_integer([:positive])}.tsv")
    Process.put({__MODULE__, :tmp_path}, path)
    path
  end

  defp format_error({:compile_failed, status, message}),
    do: "compile status #{status}: #{message}"

  defp format_error({:execution_failed, status, message}),
    do: "execution status #{status}: #{message}"

  defp format_error({:invalid_output, line}),
    do: "invalid output #{inspect(line)}"

  defp format_error(other), do: inspect(other)
end
