defmodule ClawCode.CLI do
  alias ClawCode.{Manifest, Permissions, Registry, Router, Runtime, SessionStore, Symphony}

  @switches [
    limit: :integer,
    query: :string,
    deny_tool: :keep,
    deny_prefix: :keep,
    provider: :string,
    model: :string,
    base_url: :string,
    api_key: :string,
    session_id: :string,
    max_turns: :integer,
    allow_shell: :boolean,
    allow_write: :boolean,
    native: :boolean,
    no_native: :boolean
  ]

  def main(argv) do
    Application.ensure_all_started(:claw_code)
    System.halt(run(argv))
  end

  def run(argv) do
    case argv do
      ["summary" | _rest] ->
        IO.puts(Manifest.render_summary())
        0

      ["manifest" | _rest] ->
        IO.puts(Manifest.render_manifest())
        0

      ["doctor" | _rest] ->
        IO.puts(Manifest.render_doctor())
        0

      ["commands" | rest] ->
        {opts, _args, _invalid} = OptionParser.parse(rest, strict: @switches)
        limit = Keyword.get(opts, :limit, 20)
        query = opts[:query]

        entries =
          if query do
            Registry.find(:command, query, limit: limit)
          else
            Registry.commands() |> Enum.take(limit)
          end

        IO.puts(render_index("Command entries", Registry.stats().commands, entries))
        0

      ["tools" | rest] ->
        {opts, _args, _invalid} = OptionParser.parse(rest, strict: @switches)
        context = permission_context(opts)
        limit = Keyword.get(opts, :limit, 20)
        query = opts[:query]

        entries =
          if query do
            Registry.find(:tool, query, limit: limit, permission_context: context)
          else
            Registry.tools(context) |> Enum.take(limit)
          end

        IO.puts(render_index("Tool entries", Registry.stats().tools, entries))
        0

      ["route" | rest] ->
        {opts, args, _invalid} = OptionParser.parse(rest, strict: @switches)
        opts = normalize_opts(opts)
        prompt = join_args(args)

        matches =
          Router.route(prompt,
            limit: Keyword.get(opts, :limit, 5),
            native: Keyword.get(opts, :native, true)
          )

        Enum.each(matches, fn match ->
          IO.puts("#{match.kind}\t#{match.name}\t#{match.score}\t#{match.source_hint}")
        end)

        0

      ["bootstrap" | rest] ->
        {opts, args, _invalid} = OptionParser.parse(rest, strict: @switches)
        opts = normalize_opts(opts)
        IO.puts(Runtime.bootstrap(join_args(args), opts))
        0

      ["chat" | rest] ->
        {opts, args, _invalid} = OptionParser.parse(rest, strict: @switches)
        opts = normalize_opts(opts)
        result = Runtime.chat(join_args(args), opts)
        IO.puts(render_chat_result(result))
        0

      ["resume-session", session_id | rest] ->
        {opts, args, _invalid} = OptionParser.parse(rest, strict: @switches)

        opts =
          opts
          |> Keyword.put(:session_id, session_id)
          |> normalize_opts()

        result = Runtime.chat(join_args(args), opts)
        IO.puts(render_chat_result(result))
        0

      ["symphony" | rest] ->
        {opts, args, _invalid} = OptionParser.parse(rest, strict: @switches)
        opts = normalize_opts(opts)
        result = Symphony.run(join_args(args), opts)
        IO.puts(Symphony.render(result))
        0

      ["turn-loop" | rest] ->
        run(["chat" | rest])

      ["show-command", name | _rest] ->
        case Registry.get(:command, name) do
          nil ->
            IO.puts("Command not found: #{name}")
            1

          entry ->
            IO.puts(Enum.join([entry.name, entry.source_hint, entry.responsibility], "\n"))
            0
        end

      ["show-tool", name | rest] ->
        {opts, _args, _invalid} = OptionParser.parse(rest, strict: @switches)

        case Registry.get(:tool, name, permission_context(opts)) do
          nil ->
            IO.puts("Tool not found: #{name}")
            1

          entry ->
            IO.puts(Enum.join([entry.name, entry.source_hint, entry.responsibility], "\n"))
            0
        end

      ["exec-command", name | rest] ->
        prompt = join_args(rest)

        case Registry.get(:command, name) do
          nil ->
            IO.puts("Unknown mirrored command: #{name}")
            1

          entry ->
            IO.puts(
              "Mirrored command '#{entry.name}' from #{entry.source_hint} would handle prompt #{inspect(prompt)}."
            )

            0
        end

      ["exec-tool", name | rest] ->
        payload = join_args(rest)

        case Registry.get(:tool, name) do
          nil ->
            IO.puts("Unknown mirrored tool: #{name}")
            1

          entry ->
            IO.puts(
              "Mirrored tool '#{entry.name}' from #{entry.source_hint} would handle payload #{inspect(payload)}."
            )

            0
        end

      ["load-session", session_id | _rest] ->
        session = SessionStore.load(session_id)
        requirements = session["requirements"] || []
        tool_receipts = session["tool_receipts"] || []
        messages = session["messages"] || []

        IO.puts(
          "#{session["id"]}\ncreated=#{session["created_at"] || session["saved_at"]}\nupdated=#{session["updated_at"] || session["saved_at"]}\n#{length(messages)} messages\nrequirements=#{length(requirements)}\ntool_receipts=#{length(tool_receipts)}\nstop=#{session["stop_reason"]}"
        )

        0

      _ ->
        IO.puts(help())
        1
    end
  end

  defp render_index(label, total, entries) do
    [
      "#{label}: #{total}",
      "",
      Enum.map_join(entries, "\n", fn entry -> "- #{entry.name} - #{entry.source_hint}" end)
    ]
    |> Enum.join("\n")
  end

  defp render_chat_result(result) do
    [
      "# Chat Result",
      "",
      "Provider: #{result.provider}",
      "Turns: #{result.turns}",
      "Stop reason: #{result.stop_reason}",
      "Session id: #{result.session_id}",
      "Session path: #{result.session_path}",
      "Tool receipts: #{length(result.tool_receipts)}",
      "",
      result.output
    ]
    |> Enum.join("\n")
  end

  defp permission_context(opts) do
    Permissions.new(
      deny_tools: Keyword.get_values(opts, :deny_tool),
      deny_prefixes: Keyword.get_values(opts, :deny_prefix)
    )
  end

  defp join_args(args) do
    args
    |> Enum.join(" ")
    |> String.trim()
  end

  defp normalize_opts(opts) do
    if Keyword.get(opts, :no_native, false) do
      Keyword.put(opts, :native, false)
    else
      opts
    end
  end

  defp help do
    """
    claw_code <command>

    Commands:
      summary
      manifest
      doctor
      commands [--limit N] [--query TEXT]
      tools [--limit N] [--query TEXT] [--deny-tool NAME] [--deny-prefix PREFIX]
      route <prompt> [--limit N] [--native|--no-native]
      bootstrap <prompt> [--limit N] [--native|--no-native]
      chat <prompt> [--session-id ID] [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--max-turns N] [--allow-shell] [--allow-write] [--native|--no-native]
      resume-session <session_id> <prompt> [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--max-turns N] [--allow-shell] [--allow-write] [--native|--no-native]
      symphony <prompt> [--limit N] [--native|--no-native]
      turn-loop <prompt> ...
      show-command <name>
      show-tool <name>
      exec-command <name> <prompt>
      exec-tool <name> <payload>
      load-session <session_id>
    """
  end
end
