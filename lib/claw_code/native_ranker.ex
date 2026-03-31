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
    ensure_compiled!()

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

    case System.cmd(@binary_path, [tmp_path], stderr_to_stdout: true) do
      {output, 0} -> parse_output(output)
      {output, _status} -> raise "native ranker failed: #{String.trim(output)}"
    end
  after
    if tmp_path = Process.get({__MODULE__, :tmp_path}) do
      File.rm(tmp_path)
      Process.delete({__MODULE__, :tmp_path})
    end
  end

  defp ensure_compiled! do
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
        {output, _status} -> raise "failed to compile Zig ranker: #{String.trim(output)}"
      end
    end
  end

  defp parse_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "\t", parts: 4) do
        [kind, name, source_hint, score] ->
          %{
            kind: String.to_existing_atom(kind),
            name: name,
            source_hint: source_hint,
            score: String.to_integer(score)
          }

        _ ->
          raise "invalid native ranker output: #{inspect(line)}"
      end
    end)
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
end
