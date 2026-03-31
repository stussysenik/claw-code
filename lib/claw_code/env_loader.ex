defmodule ClawCode.EnvLoader do
  @default_files [".env.local", ".env"]

  def load(opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    files = Keyword.get(opts, :files, @default_files)

    Enum.each(files, fn relative_path ->
      path = Path.expand(relative_path, cwd)

      if File.regular?(path) do
        path
        |> File.read!()
        |> parse()
        |> Enum.each(fn {key, value} ->
          if System.get_env(key) in [nil, ""] do
            System.put_env(key, value)
          end
        end)
      end
    end)

    :ok
  end

  def parse(contents) when is_binary(contents) do
    contents
    |> String.split(~r/\r?\n/, trim: true)
    |> Enum.reduce([], fn line, acc ->
      case parse_line(line) do
        nil -> acc
        pair -> [pair | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp parse_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        nil

      String.starts_with?(trimmed, "#") ->
        nil

      true ->
        trimmed
        |> String.trim_leading("export ")
        |> String.split("=", parts: 2)
        |> case do
          [key, value] ->
            normalized_key = String.trim(key)

            if normalized_key == "" do
              nil
            else
              {normalized_key, normalize_value(value)}
            end

          _other ->
            nil
        end
    end
  end

  defp normalize_value(value) do
    value
    |> String.trim()
    |> strip_inline_comment()
    |> strip_quotes()
  end

  defp strip_inline_comment(value) do
    case Regex.run(~r/^(.*?)(\s+#.*)?$/, value, capture: :all_but_first) do
      [content, _comment] -> String.trim(content)
      [content] -> String.trim(content)
      _other -> value
    end
  end

  defp strip_quotes("\"" <> rest) do
    rest
    |> String.trim_trailing("\"")
    |> String.replace("\\n", "\n")
    |> String.replace("\\\"", "\"")
  end

  defp strip_quotes("'" <> rest) do
    String.trim_trailing(rest, "'")
  end

  defp strip_quotes(value), do: value
end
