defmodule ClawCode.Router do
  alias ClawCode.{Entry, NativeRanker, Permissions, Registry}

  defmodule Match do
    @enforce_keys [:kind, :name, :source_hint, :score]
    defstruct [:kind, :name, :source_hint, :score]
  end

  def route(prompt, opts \\ []) do
    context = Keyword.get(opts, :permission_context, Permissions.new())
    limit = Keyword.get(opts, :limit, 5)
    use_native = Keyword.get(opts, :native, true)
    native_ranker = Keyword.get(opts, :native_ranker, NativeRanker)
    entries = Registry.entries(:all, context)

    ranked =
      if use_native and native_ranker.available?() do
        case native_ranker.safe_rank(prompt, entries) do
          {:ok, rows} -> native_matches(rows, entries)
          {:error, _reason} -> pure_rank(prompt, entries)
        end
      else
        pure_rank(prompt, entries)
      end

    ranked
    |> Enum.filter(&(&1.score > 0))
    |> select_balanced(limit)
  end

  def pure_rank(prompt, entries) do
    prompt_tokens = tokens(prompt)

    entries
    |> Enum.map(fn %Entry{} = entry ->
      haystacks = [
        String.downcase(entry.name),
        String.downcase(entry.source_hint),
        String.downcase(entry.responsibility)
      ]

      score =
        Enum.reduce(prompt_tokens, 0, fn token, acc ->
          bonus =
            cond do
              String.downcase(entry.name) == token -> 3
              Enum.any?(haystacks, &String.contains?(&1, token)) -> 1
              true -> 0
            end

          acc + bonus
        end)

      %Match{kind: entry.kind, name: entry.name, source_hint: entry.source_hint, score: score}
    end)
    |> Enum.sort_by(&{-&1.score, &1.kind, &1.name})
  end

  defp native_matches(rows, entries) do
    scores =
      rows
      |> Map.new(fn row -> {{row.kind, row.name, row.source_hint}, row.score} end)

    entries
    |> Enum.map(fn %Entry{} = entry ->
      score = Map.get(scores, {entry.kind, entry.name, entry.source_hint}, 0)
      %Match{kind: entry.kind, name: entry.name, source_hint: entry.source_hint, score: score}
    end)
    |> Enum.sort_by(&{-&1.score, &1.kind, &1.name})
  end

  defp select_balanced(matches, limit) do
    by_kind = Enum.group_by(matches, & &1.kind)
    chosen = Enum.take(by_kind[:command] || [], 1) ++ Enum.take(by_kind[:tool] || [], 1)

    leftovers =
      matches |> Enum.reject(&(&1 in chosen)) |> Enum.take(max(limit - length(chosen), 0))

    Enum.take(chosen ++ leftovers, limit)
  end

  defp tokens(value) do
    value
    |> String.downcase()
    |> String.split(~r/[^[:alnum:]_]+/u, trim: true)
    |> Enum.uniq()
  end
end
