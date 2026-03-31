defmodule ClawCode.Runtime do
  alias ClawCode.{Router, SessionServer, SessionStore}
  alias ClawCode.Providers.OpenAICompatible
  alias ClawCode.Tools.Builtin

  defmodule Result do
    @enforce_keys [:prompt, :output, :stop_reason, :session_path, :turns, :provider]
    defstruct [
      :prompt,
      :output,
      :stop_reason,
      :session_path,
      :session_id,
      :turns,
      :provider,
      :requirements,
      tool_receipts: [],
      routed_matches: [],
      matched_commands: [],
      matched_tools: [],
      messages: []
    ]
  end

  def bootstrap(prompt, opts \\ []) do
    config = OpenAICompatible.resolve_config(opts)
    matches = Router.route(prompt, route_opts(opts))

    [
      "# Bootstrap",
      "",
      "Prompt: #{prompt}",
      "Provider: #{config.provider}",
      "Configured: #{OpenAICompatible.configured?(config)}",
      "",
      "## Routed Matches",
      render_matches(matches),
      "",
      "## Local Tools",
      Enum.map_join(Builtin.maybe_enabled_names(opts), "\n", &"- #{&1}")
    ]
    |> Enum.join("\n")
  end

  def chat(prompt, opts \\ []) do
    config = OpenAICompatible.resolve_config(opts)
    matches = Router.route(prompt, route_opts(opts))

    {:ok, session_id, session_pid} =
      SessionServer.ensure_started(opts[:session_id], session_server_opts(opts))

    session = SessionServer.snapshot(session_pid)
    messages = seed_messages(prompt, matches, session["messages"] || [])
    existing_receipts = session["tool_receipts"] || []
    existing_turns = session["turns"] || 0

    if OpenAICompatible.configured?(config) do
      tool_specs = Builtin.specs(opts)

      case loop(
             messages,
             config,
             tool_specs,
             opts,
             1,
             Keyword.get(opts, :max_turns, 6),
             existing_receipts
           ) do
        {:ok, final_messages, output, stop_reason, turns, receipts} ->
          persist_result(
            session_pid,
            prompt,
            output,
            stop_reason,
            existing_turns + turns,
            config,
            matches,
            final_messages,
            receipts,
            session_id
          )

        {:error, message, final_messages, receipts} ->
          persist_result(
            session_pid,
            prompt,
            message,
            "provider_error",
            existing_turns,
            config,
            matches,
            final_messages,
            receipts,
            session_id
          )
      end
    else
      persist_result(
        session_pid,
        prompt,
        missing_provider_message(config),
        "missing_provider_config",
        existing_turns,
        config,
        matches,
        messages,
        existing_receipts,
        session_id
      )
    end
  end

  defp loop(messages, _config, _tools, _opts, turn, max_turns, receipts) when turn > max_turns do
    {:ok, messages, "Tool loop limit reached.", "max_turns_reached", max_turns, receipts}
  end

  defp loop(messages, config, tools, opts, turn, max_turns, receipts) do
    case OpenAICompatible.chat(config, messages, tools: tools) do
      {:ok, %{"choices" => [%{"message" => message} | _]}} ->
        assistant_message = normalize_assistant_message(message)

        case tool_calls_from(message) do
          [] ->
            {:ok, messages ++ [assistant_message], content_from(message), "completed", turn,
             receipts}

          tool_calls ->
            {tool_messages, new_receipts} =
              Enum.map(tool_calls, fn tool_call ->
                execute_tool_call(tool_call, opts)
              end)
              |> Enum.unzip()

            loop(
              messages ++ [assistant_message] ++ tool_messages,
              config,
              tools,
              opts,
              turn + 1,
              max_turns,
              receipts ++ new_receipts
            )
        end

      {:ok, _unexpected} ->
        {:error, "provider returned no choices", messages, receipts}

      {:error, reason} ->
        {:error, reason, messages, receipts}
    end
  end

  defp execute_tool_call(
         %{"id" => id, "function" => %{"name" => name, "arguments" => arguments}},
         opts
       ) do
    parsed_arguments =
      case Jason.decode(arguments) do
        {:ok, decoded} -> decoded
        {:error, _reason} -> %{"raw" => arguments}
      end

    {content, receipt} =
      case Builtin.execute_with_receipt(name, parsed_arguments, opts) do
        {:ok, output, receipt} ->
          {output, normalize_tool_receipt(receipt, id, name, parsed_arguments)}

        {:error, message, receipt} ->
          {"error: #{message}", normalize_tool_receipt(receipt, id, name, parsed_arguments)}
      end

    {
      %{
        "role" => "tool",
        "tool_call_id" => id,
        "name" => name,
        "content" => content
      },
      receipt
    }
  end

  defp persist_result(
         session_pid,
         prompt,
         output,
         stop_reason,
         turns,
         config,
         matches,
         messages,
         tool_receipts,
         session_id
       ) do
    requirements = SessionStore.requirements_ledger()

    payload = %{
      id: session_id,
      prompt: prompt,
      output: output,
      stop_reason: stop_reason,
      turns: turns,
      provider: Map.from_struct(config),
      routed_matches: Enum.map(matches, &Map.from_struct/1),
      messages: messages,
      tool_receipts: tool_receipts,
      requirements: requirements
    }

    {path, document} = SessionServer.persist(session_pid, payload)

    %Result{
      prompt: prompt,
      output: output,
      stop_reason: stop_reason,
      session_path: path,
      session_id: document["id"],
      turns: turns,
      provider: config.provider,
      requirements: requirements,
      tool_receipts: tool_receipts,
      routed_matches: matches,
      matched_commands: Enum.filter(matches, &(&1.kind == :command)),
      matched_tools: Enum.filter(matches, &(&1.kind == :tool)),
      messages: messages
    }
  end

  defp seed_messages(prompt, matches, existing_messages) do
    case existing_messages do
      [] ->
        [
          %{"role" => "system", "content" => system_prompt(matches)},
          %{"role" => "user", "content" => prompt}
        ]

      messages ->
        messages ++ [%{"role" => "user", "content" => prompt}]
    end
  end

  defp system_prompt(matches) do
    routed_context =
      matches
      |> Enum.map(fn match -> "- #{match.kind}: #{match.name} (#{match.source_hint})" end)
      |> Enum.join("\n")

    """
    You are Claw Code Elixir, an Elixir-first coding assistant.
    Keep outputs concise, deterministic, and terminal-friendly.
    Prefer project-relative paths and explain tool usage briefly.

    Routed context:
    #{if routed_context == "", do: "- none", else: routed_context}
    """
    |> String.trim()
  end

  defp route_opts(opts) do
    [
      limit: Keyword.get(opts, :limit, 5),
      native: Keyword.get(opts, :native, true)
    ]
  end

  defp render_matches([]), do: "- none"

  defp render_matches(matches) do
    Enum.map_join(matches, "\n", fn match ->
      "- [#{match.kind}] #{match.name} (#{match.score}) - #{match.source_hint}"
    end)
  end

  defp tool_calls_from(%{"tool_calls" => tool_calls}) when is_list(tool_calls), do: tool_calls
  defp tool_calls_from(_message), do: []

  defp normalize_assistant_message(message) do
    %{
      "role" => "assistant",
      "content" => content_from(message)
    }
    |> maybe_put("tool_calls", message["tool_calls"], is_list(message["tool_calls"]))
  end

  defp content_from(%{"content" => nil}), do: ""
  defp content_from(%{"content" => content}) when is_binary(content), do: content

  defp content_from(%{"content" => content}) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{"type" => "text", "text" => text} -> text
      %{"text" => text} -> text
      other -> Jason.encode!(other)
    end)
  end

  defp content_from(_message), do: ""

  defp missing_provider_message(config) do
    envs = OpenAICompatible.required_env_vars(config.provider)

    "Missing provider configuration for #{config.provider}. " <>
      "Set base_url from #{Enum.join(envs.base_url, "/")}, " <>
      "api_key from #{Enum.join(envs.api_key, "/")}, " <>
      "and model from #{Enum.join(envs.model, "/")}."
  end

  defp normalize_tool_receipt(receipt, id, name, arguments) do
    Map.merge(receipt, %{
      tool_call_id: id,
      tool_name: name,
      argument_keys: arguments |> Map.keys() |> Enum.sort()
    })
  end

  defp session_server_opts(opts) do
    case Keyword.get(opts, :session_root) do
      nil -> []
      root -> [root: root]
    end
  end

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
