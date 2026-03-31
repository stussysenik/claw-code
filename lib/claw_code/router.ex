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
    entries = Registry.entries(:all, context)

    try do
      ranked =
        if use_native and NativeRanker.available?() do
          native_rank(prompt, entries)
        else
          pure_rank(prompt, entries)
        end

      ranked
      |> Enum.filter(&(&1.score > 0))
      |> select_balanced(limit)
    rescue
      _error ->
        prompt
        |> pure_rank(entries)
        |> Enum.filter(&(&1.score > 0))
        |> select_balanced(limit)
    end
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

  defp native_rank(prompt, entries) do
    scores =
      NativeRanker.rank(prompt, entries)
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
