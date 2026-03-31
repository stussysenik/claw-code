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

    case SessionServer.begin_run(session_pid) do
      {:ok, session} ->
        messages = seed_messages(prompt, matches, session["messages"] || [])
        existing_receipts = session["tool_receipts"] || []
        existing_turns = session["turns"] || 0

        context = %{
          prompt: prompt,
          config: config,
          matches: matches,
          opts: opts,
          session_id: session_id,
          session_pid: session_pid,
          existing_turns: existing_turns,
          requirements: SessionStore.requirements_ledger()
        }

        checkpoint_result(session_pid, context, messages, existing_receipts, existing_turns)

        if OpenAICompatible.configured?(config) do
          task =
            Task.Supervisor.async_nolink(ClawCode.TaskSupervisor, fn ->
              run_chat_session(context, messages, existing_receipts)
            end)

          case SessionServer.attach_run(session_pid, task.pid) do
            :ok ->
              await_run(task, context)

            {:error, :not_running} ->
              _ = Task.shutdown(task, :brutal_kill)
              interrupted_result(context)
          end
        else
          finalize_result(
            session_pid,
            prompt,
            missing_provider_message(config),
            "missing_provider_config",
            existing_turns,
            config,
            matches,
            messages,
            existing_receipts,
            session_id,
            context.requirements
          )
        end

      {:error, :session_busy, session} ->
        busy_result(session_id, session, config, matches, prompt, opts)
    end
  end

  def cancel(session_id, opts \\ []) do
    case SessionStore.fetch(session_id, session_server_opts(opts)) do
      {:ok, _session} ->
        with {:ok, ^session_id, session_pid} <-
               SessionServer.ensure_started(session_id, session_server_opts(opts)) do
          SessionServer.cancel_run(session_pid)
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp run_chat_session(context, messages, existing_receipts) do
    tool_specs = tool_specs_for_prompt(context.prompt, context.matches, context.opts)

    case loop(
           context.session_pid,
           context,
           messages,
           context.config,
           tool_specs,
           context.opts,
           1,
           Keyword.get(context.opts, :max_turns, 6),
           existing_receipts
         ) do
      {:ok, final_messages, output, stop_reason, turns, receipts} ->
        finalize_result(
          context.session_pid,
          context.prompt,
          output,
          stop_reason,
          context.existing_turns + turns,
          context.config,
          context.matches,
          final_messages,
          receipts,
          context.session_id,
          context.requirements
        )

      {:error, message, final_messages, receipts, turns} ->
        finalize_result(
          context.session_pid,
          context.prompt,
          message,
          "provider_error",
          context.existing_turns + turns,
          context.config,
          context.matches,
          final_messages,
          receipts,
          context.session_id,
          context.requirements
        )
    end
  end

  defp loop(_session_pid, _context, messages, _config, _tools, _opts, turn, max_turns, receipts)
       when turn > max_turns do
    {:ok, messages, "Tool loop limit reached.", "max_turns_reached", max_turns, receipts}
  end

  defp loop(session_pid, context, messages, config, tools, opts, turn, max_turns, receipts) do
    case OpenAICompatible.chat(config, messages, tools: tools) do
      {:ok, response} ->
        case OpenAICompatible.assistant_message(response) do
          {:ok, message} ->
            assistant_message = normalize_assistant_message(message)
            assistant_messages = messages ++ [assistant_message]

            checkpoint_result(
              session_pid,
              context,
              assistant_messages,
              receipts,
              context.existing_turns + turn
            )

            case tool_calls_from(message) do
              [] ->
                {:ok, assistant_messages, content_from(message), "completed", turn, receipts}

              tool_calls ->
                {tool_messages, new_receipts} =
                  Enum.map(tool_calls, fn tool_call ->
                    execute_tool_call(tool_call, opts, turn)
                  end)
                  |> Enum.unzip()

                next_messages = assistant_messages ++ tool_messages
                next_receipts = receipts ++ new_receipts

                checkpoint_result(
                  session_pid,
                  context,
                  next_messages,
                  next_receipts,
                  context.existing_turns + turn
                )

                loop(
                  session_pid,
                  context,
                  next_messages,
                  config,
                  tools,
                  opts,
                  turn + 1,
                  max_turns,
                  next_receipts
                )
            end

          :error ->
            {:error, "provider returned no choices", messages, receipts, max(turn - 1, 0)}
        end

      {:error, reason} ->
        if tools != [] and tool_policy(opts) == :auto and
             OpenAICompatible.tooling_unsupported?(reason) do
          loop(session_pid, context, messages, config, [], opts, turn, max_turns, receipts)
        else
          {:error, reason, messages, receipts, max(turn - 1, 0)}
        end
    end
  end

  defp execute_tool_call(
         %{"id" => id, "function" => %{"name" => name, "arguments" => arguments}},
         opts,
         turn
       ) do
    parsed_arguments = parse_tool_arguments(arguments)

    {content, receipt} =
      case Builtin.execute_with_receipt(name, parsed_arguments, opts) do
        {:ok, output, receipt} ->
          {output, normalize_tool_receipt(receipt, id, name, parsed_arguments, turn)}

        {:error, message, receipt} ->
          {"error: #{message}", normalize_tool_receipt(receipt, id, name, parsed_arguments, turn)}
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

  defp execute_tool_call(_tool_call, _opts, turn) do
    receipt =
      normalize_tool_receipt(
        %{status: "error", output: "invalid tool call", exit_status: "error", cwd: File.cwd!()},
        "invalid-tool-call-#{turn}",
        "invalid_tool_call",
        %{},
        turn
      )

    {
      %{
        "role" => "tool",
        "tool_call_id" => receipt.tool_call_id,
        "name" => receipt.tool_name,
        "content" => "error: invalid tool call"
      },
      receipt
    }
  end

  defp parse_tool_arguments(arguments) when is_map(arguments), do: arguments

  defp parse_tool_arguments(arguments) when is_binary(arguments) do
    case Jason.decode(arguments) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> %{"raw" => arguments}
    end
  end

  defp parse_tool_arguments(nil), do: %{}
  defp parse_tool_arguments(arguments), do: %{"raw" => inspect(arguments)}

  defp finalize_result(
         session_pid,
         prompt,
         output,
         stop_reason,
         turns,
         config,
         matches,
         messages,
         tool_receipts,
         session_id,
         requirements
       ) do
    payload = %{
      id: session_id,
      prompt: prompt,
      output: output,
      stop_reason: stop_reason,
      turns: turns,
      provider: provider_snapshot(config),
      routed_matches: Enum.map(matches, &Map.from_struct/1),
      messages: messages,
      tool_receipts: tool_receipts,
      requirements: requirements
    }

    {path, document} = SessionServer.finish_run(session_pid, payload)

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

  defp checkpoint_result(session_pid, context, messages, tool_receipts, turns) do
    SessionServer.checkpoint(session_pid, %{
      id: context.session_id,
      prompt: context.prompt,
      turns: turns,
      provider: provider_snapshot(context.config),
      routed_matches: Enum.map(context.matches, &Map.from_struct/1),
      messages: messages,
      tool_receipts: tool_receipts,
      requirements: context.requirements
    })
  end

  defp await_run(task, context) do
    case Task.yield(task, :infinity) do
      {:ok, result} ->
        result

      {:exit, _reason} ->
        interrupted_result(context)

      nil ->
        _ = Task.shutdown(task, :brutal_kill)
        interrupted_result(context)
    end
  end

  defp busy_result(session_id, session, config, matches, prompt, opts) do
    %Result{
      prompt: prompt,
      output: "Session #{session_id} already has an active run.",
      stop_reason: "session_busy",
      session_path: SessionStore.path(session_id, session_server_opts(opts)),
      session_id: session_id,
      turns: session["turns"] || 0,
      provider: config.provider,
      requirements: session["requirements"] || SessionStore.requirements_ledger(),
      tool_receipts: session["tool_receipts"] || [],
      routed_matches: matches,
      matched_commands: Enum.filter(matches, &(&1.kind == :command)),
      matched_tools: Enum.filter(matches, &(&1.kind == :tool)),
      messages: session["messages"] || []
    }
  end

  defp interrupted_result(context) do
    session = SessionServer.snapshot(context.session_pid)
    stop_reason = session["stop_reason"] || "run_interrupted"

    %Result{
      prompt: context.prompt,
      output: session["output"] || "Session run ended before a final reply was returned.",
      stop_reason: stop_reason,
      session_path: SessionStore.path(context.session_id, session_server_opts(context.opts)),
      session_id: context.session_id,
      turns: session["turns"] || context.existing_turns,
      provider: context.config.provider,
      requirements: session["requirements"] || context.requirements,
      tool_receipts: session["tool_receipts"] || [],
      routed_matches: context.matches,
      matched_commands: Enum.filter(context.matches, &(&1.kind == :command)),
      matched_tools: Enum.filter(context.matches, &(&1.kind == :tool)),
      messages: session["messages"] || []
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

  def tool_policy(opts \\ []) do
    case requested_tool_policy(opts) do
      nil ->
        System.get_env("CLAW_TOOL_MODE")
        |> normalize_tool_policy()
        |> Kernel.||(:auto)

      policy ->
        policy
    end
  end

  defp tool_specs_for_prompt(prompt, matches, opts) do
    if expose_tools?(prompt, matches, opts) do
      Builtin.specs(opts)
    else
      []
    end
  end

  defp expose_tools?(prompt, _matches, opts) do
    case tool_policy(opts) do
      :enabled ->
        true

      :disabled ->
        false

      :auto ->
        if Keyword.get(opts, :allow_shell, false) or Keyword.get(opts, :allow_write, false) do
          true
        else
          prompt_text = String.downcase(prompt || "")

          Regex.match?(
            ~r/\b(repo|repository|project|file|files|path|read|inspect|review|search|list|command|tool|terminal|shell|write|edit|fix|refactor|test|build|compile|session)\b/,
            prompt_text
          )
        end
    end
  end

  defp requested_tool_policy(opts) do
    cond do
      Keyword.get(opts, :tools) == true -> :enabled
      Keyword.get(opts, :tools) == false -> :disabled
      true -> nil
    end
  end

  defp normalize_tool_policy(nil), do: nil

  defp normalize_tool_policy(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "1" -> :enabled
      "true" -> :enabled
      "on" -> :enabled
      "enable" -> :enabled
      "enabled" -> :enabled
      "force" -> :enabled
      "0" -> :disabled
      "false" -> :disabled
      "off" -> :disabled
      "disable" -> :disabled
      "disabled" -> :disabled
      "auto" -> :auto
      _other -> nil
    end
  end

  defp render_matches([]), do: "- none"

  defp render_matches(matches) do
    Enum.map_join(matches, "\n", fn match ->
      "- [#{match.kind}] #{match.name} (#{match.score}) - #{match.source_hint}"
    end)
  end

  defp tool_calls_from(%{"tool_calls" => tool_calls}) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(&normalize_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp tool_calls_from(%{"function_call" => %{"name" => name} = function_call})
       when is_binary(name) do
    [
      %{
        "id" => function_call["id"] || "function-call-#{name}",
        "function" => %{
          "name" => name,
          "arguments" => normalize_tool_arguments(function_call["arguments"])
        }
      }
    ]
  end

  defp tool_calls_from(_message), do: []

  defp normalize_assistant_message(message) do
    %{
      "role" => "assistant",
      "content" => content_from(message)
    }
    |> maybe_put("tool_calls", message["tool_calls"], is_list(message["tool_calls"]))
  end

  defp content_from(message), do: OpenAICompatible.message_content(message)

  defp normalize_tool_call(%{"function" => %{"name" => name} = function} = tool_call)
       when is_binary(name) do
    %{
      "id" => tool_call["id"] || "tool-call-#{name}",
      "function" => %{
        "name" => name,
        "arguments" => normalize_tool_arguments(function["arguments"])
      }
    }
  end

  defp normalize_tool_call(_tool_call), do: nil

  defp normalize_tool_arguments(arguments) when is_binary(arguments), do: arguments
  defp normalize_tool_arguments(arguments) when is_map(arguments), do: Jason.encode!(arguments)
  defp normalize_tool_arguments(nil), do: "{}"
  defp normalize_tool_arguments(arguments), do: Jason.encode!(%{"raw" => inspect(arguments)})

  defp missing_provider_message(config) do
    envs = OpenAICompatible.required_env_vars(config.provider)
    required_fields = OpenAICompatible.required_fields(config.provider)

    hints =
      [
        if(:base_url in required_fields, do: "base_url from #{Enum.join(envs.base_url, "/")}"),
        if(:api_key in required_fields, do: "api_key from #{Enum.join(envs.api_key, "/")}"),
        if(:model in required_fields, do: "model from #{Enum.join(envs.model, "/")}")
      ]
      |> Enum.reject(&is_nil/1)

    "Missing provider configuration for #{config.provider}. " <>
      "Set #{render_hints(hints)}."
  end

  defp normalize_tool_receipt(receipt, id, name, arguments, turn) do
    Map.merge(receipt, %{
      turn: turn,
      tool_call_id: id,
      tool_name: name,
      argument_keys: arguments |> Map.keys() |> Enum.sort()
    })
  end

  defp provider_snapshot(config) do
    %{
      provider: config.provider,
      base_url: config.base_url,
      api_key_header: config.api_key_header,
      model: config.model,
      api_key_present: is_binary(config.api_key) and config.api_key != ""
    }
  end

  defp session_server_opts(opts) do
    case Keyword.get(opts, :session_root) do
      nil -> []
      root -> [root: root]
    end
  end

  defp render_hints([hint]), do: hint
  defp render_hints([left, right]), do: left <> " and " <> right

  defp render_hints(hints) do
    {head, [last]} = Enum.split(hints, length(hints) - 1)
    Enum.join(head, ", ") <> ", and " <> last
  end

  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
end
