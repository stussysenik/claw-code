defmodule ClawCode.CLI do
  alias ClawCode.{Manifest, Permissions, Registry, Router, Runtime, SessionStore, Symphony}
  alias ClawCode.Providers.OpenAICompatible

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
    show_messages: :boolean,
    show_receipts: :boolean,
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

      ["doctor" | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest, validate_provider: true) do
          IO.puts(Manifest.render_doctor(opts))
          0
        else
          {:error, message} ->
            IO.puts(message)
            1
        end

      ["sessions" | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest) do
          limit = Keyword.get(opts, :limit, 20)
          IO.puts(render_sessions(SessionStore.list(limit: limit)))
          0
        else
          {:error, message} ->
            IO.puts(message)
            1
        end

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
        with {:ok, opts, args} <- parse_opts(rest, validate_provider: true) do
          IO.puts(Runtime.bootstrap(join_args(args), opts))
          0
        else
          {:error, message} ->
            IO.puts(message)
            1
        end

      ["chat" | rest] ->
        with {:ok, opts, args} <- parse_opts(rest, validate_provider: true) do
          run_chat(join_args(args), opts)
        else
          {:error, message} ->
            IO.puts(message)
            1
        end

      ["resume-session", session_id | rest] ->
        with {:ok, opts, args} <- parse_opts(rest, validate_provider: true) do
          opts = Keyword.put(opts, :session_id, session_id)
          run_chat(join_args(args), opts)
        else
          {:error, message} ->
            IO.puts(message)
            1
        end

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

      ["load-session", session_id | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest),
             {:ok, session} <- SessionStore.fetch(session_id) do
          IO.puts(render_session(session, opts))
          0
        else
          :error ->
            IO.puts("Session not found: #{session_id}")
            1

          {:error, message} ->
            IO.puts(message)
            1
        end

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
      render_last_receipt(result.tool_receipts),
      "",
      result.output
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp render_sessions([]) do
    "# Sessions\n\nnone"
  end

  defp render_sessions(sessions) do
    [
      "# Sessions",
      "",
      Enum.map_join(sessions, "\n", fn session ->
        id = session["id"]
        updated_at = session["updated_at"] || session["saved_at"] || "unknown"
        stop_reason = session["stop_reason"] || "unknown"
        messages = length(session["messages"] || [])
        receipts = length(session["tool_receipts"] || [])

        "#{id}\t#{updated_at}\tstop=#{stop_reason}\tmessages=#{messages}\treceipts=#{receipts}"
      end)
    ]
    |> Enum.join("\n")
  end

  defp render_session(session, opts) do
    requirements = session["requirements"] || []
    tool_receipts = session["tool_receipts"] || []
    messages = session["messages"] || []

    [
      session["id"],
      "created=#{session["created_at"] || session["saved_at"]}",
      "updated=#{session["updated_at"] || session["saved_at"]}",
      "#{length(messages)} messages",
      "requirements=#{length(requirements)}",
      "tool_receipts=#{length(tool_receipts)}",
      "stop=#{session["stop_reason"]}",
      render_messages(messages, Keyword.get(opts, :show_messages, false)),
      render_receipts(tool_receipts, Keyword.get(opts, :show_receipts, false))
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp render_messages(_messages, false), do: nil

  defp render_messages(messages, true) do
    header = "Messages:"

    body =
      messages
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {message, index} ->
        role = message["role"] || "unknown"
        content = summarize_text(message["content"])
        "#{index}. #{role}: #{content}"
      end)

    Enum.join([header, body], "\n")
  end

  defp render_receipts(_receipts, false), do: nil

  defp render_receipts(receipts, true) do
    header = "Receipts:"

    body =
      receipts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {receipt, index} ->
        started_at = receipt["started_at"] || receipt[:started_at] || "unknown"
        status = receipt["status"] || receipt[:status] || "unknown"

        tool =
          receipt["tool_name"] || receipt[:tool_name] || receipt["tool"] || receipt[:tool] ||
            receipt["command"] || receipt[:command] || "unknown"

        exit_status = receipt["exit_status"] || receipt[:exit_status] || "-"
        output = summarize_text(receipt["output"] || receipt[:output])
        "#{index}. #{started_at} #{tool} status=#{status} exit=#{exit_status} output=#{output}"
      end)

    Enum.join([header, body], "\n")
  end

  defp render_last_receipt([]), do: nil

  defp render_last_receipt(receipts) do
    receipt = List.last(receipts)
    status = receipt[:status] || receipt["status"] || "unknown"

    tool =
      receipt[:tool_name] || receipt["tool_name"] || receipt[:tool] || receipt["tool"] ||
        receipt[:command] || receipt["command"] || "unknown"

    duration_ms = receipt[:duration_ms] || receipt["duration_ms"] || "-"

    invocation =
      receipt[:invocation] || receipt["invocation"] || receipt[:path] || receipt["path"] || ""

    "Last receipt: #{tool} #{status} #{duration_ms}ms #{summarize_text(invocation)}"
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

  defp run_chat(prompt, opts) do
    result = Runtime.chat(prompt, opts)
    IO.puts(render_chat_result(result))
    chat_exit_code(result)
  end

  defp parse_opts(args, opts \\ []) do
    validate_provider? = Keyword.get(opts, :validate_provider, false)
    {parsed_opts, parsed_args, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      invalid != [] ->
        {:error,
         "Unknown options: " <>
           Enum.map_join(invalid, ", ", fn {switch, _value} ->
             switch
             |> to_string()
             |> String.trim_leading("-")
             |> String.replace("_", "-")
             |> then(&("--" <> &1))
           end)}

      validate_provider? ->
        validate_provider(parsed_opts, parsed_args)

      true ->
        {:ok, normalize_opts(parsed_opts), parsed_args}
    end
  end

  defp validate_provider(opts, args) do
    provider = OpenAICompatible.resolve_config(opts).provider

    if OpenAICompatible.valid_provider?(provider) do
      {:ok, normalize_opts(opts), args}
    else
      {:error,
       "Unknown provider: #{provider}. Expected one of: #{Enum.join(OpenAICompatible.providers(), ", ")}"}
    end
  end

  defp chat_exit_code(%{stop_reason: "completed"}), do: 0
  defp chat_exit_code(_result), do: 1

  defp normalize_opts(opts) do
    if Keyword.get(opts, :no_native, false) do
      Keyword.put(opts, :native, false)
    else
      opts
    end
  end

  defp summarize_text(nil), do: ""

  defp summarize_text(value) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(120)
  end

  defp summarize_text(value), do: value |> inspect() |> truncate(120)

  defp truncate(value, limit) when byte_size(value) <= limit, do: value
  defp truncate(value, limit), do: String.slice(value, 0, limit - 3) <> "..."

  defp help do
    """
    claw_code <command>

    Commands:
      summary
      manifest
      doctor [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY]
      sessions [--limit N]
      commands [--limit N] [--query TEXT]
      tools [--limit N] [--query TEXT] [--deny-tool NAME] [--deny-prefix PREFIX]
      route <prompt> [--limit N] [--native|--no-native]
      bootstrap <prompt> [--limit N] [--native|--no-native]
      chat <prompt> [--session-id ID] [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--max-turns N] [--allow-shell] [--allow-write] [--native|--no-native]
      resume-session <session_id> <prompt> [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--max-turns N] [--allow-shell] [--allow-write] [--native|--no-native]
      symphony <prompt> [--limit N] [--native|--no-native]
      turn-loop <prompt> ...
      show-command <name>
      show-tool <name>
      exec-command <name> <prompt>
      exec-tool <name> <payload>
      load-session <session_id> [--show-messages] [--show-receipts]
    """
  end
end
