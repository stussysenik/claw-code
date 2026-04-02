defmodule ClawCode.CLI do
  alias ClawCode.{
    Daemon,
    Manifest,
    Multimodal,
    Permissions,
    Registry,
    Router,
    Runtime,
    SessionStore,
    Symphony,
    TUI
  }

  alias ClawCode.Providers.OpenAICompatible

  @switches [
    as: :string,
    limit: :integer,
    query: :string,
    image: :keep,
    deny_tool: :keep,
    deny_prefix: :keep,
    provider: :string,
    model: :string,
    base_url: :string,
    api_key: :string,
    api_key_header: :string,
    vision_provider: :string,
    vision_model: :string,
    vision_base_url: :string,
    vision_api_key: :string,
    vision_api_key_header: :string,
    session_id: :string,
    max_turns: :integer,
    allow_shell: :boolean,
    allow_write: :boolean,
    tools: :boolean,
    no_tools: :boolean,
    json: :boolean,
    show_messages: :boolean,
    show_receipts: :boolean,
    daemon: :boolean,
    native: :boolean,
    no_native: :boolean,
    no_daemon: :boolean,
    force: :boolean,
    bin_dir: :string,
    session_root: :string,
    daemon_root: :string,
    daemon_timeout_ms: :integer
  ]

  @default_launcher "pikachu"
  @default_bin_dir "~/.local/bin"

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
          emit_value(Manifest.doctor_payload(opts), opts, fn -> Manifest.render_doctor(opts) end)
          0
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["providers" | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest, validate_provider: true) do
          emit_value(Manifest.provider_matrix_payload(opts), opts, fn ->
            Manifest.render_provider_matrix(opts)
          end)

          0
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["install" | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest),
             {:ok, payload} <- install_launcher(opts) do
          emit_value(payload, opts, fn -> render_install(payload) end)
          0
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["probe" | rest] ->
        with {:ok, opts, args} <- parse_opts(rest, validate_provider: true) do
          case OpenAICompatible.probe(Keyword.put(opts, :probe_prompt, join_args(args))) do
            {:ok, payload} ->
              emit_value(payload, opts, fn -> render_probe(payload) end)
              0

            {:error, payload} ->
              emit_value(payload, opts, fn -> render_probe(payload) end)
              1
          end
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["daemon" | rest] ->
        run_daemon(rest)

      ["sessions" | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest) do
          limit = Keyword.get(opts, :limit, 20)

          sessions =
            SessionStore.list(
              limit: limit,
              root: session_root_opt(opts),
              query: opts[:query]
            )

          emit_value(%{sessions: Enum.map(sessions, &session_summary/1)}, opts, fn ->
            render_sessions(sessions)
          end)

          0
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
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
          emit_value(%{bootstrap: Runtime.bootstrap(join_args(args), opts)}, opts, fn ->
            Runtime.bootstrap(join_args(args), opts)
          end)

          0
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["chat" | rest] ->
        with {:ok, opts, args} <- parse_opts(rest, validate_provider: true) do
          run_chat(join_args(args), opts)
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["resume-session", session_ref | rest] ->
        with {:ok, opts, args} <- parse_opts(rest, validate_provider: true) do
          case expand_session_ref(session_ref, opts) do
            {:ok, session_id} ->
              opts = Keyword.put(opts, :session_id, session_id)
              run_chat(join_args(args), opts)

            {:error, :not_found} ->
              emit_error("Session not found: #{session_ref}", json_requested?(rest))
              1
          end
        else
          {:error, message} ->
            emit_error(message, json_requested?(rest))
            1
        end

      ["cancel-session", session_ref | rest] ->
        run_cancel(session_ref, rest)

      ["symphony" | rest] ->
        {opts, args, _invalid} = OptionParser.parse(rest, strict: @switches)
        opts = normalize_opts(opts)
        result = Symphony.run(join_args(args), opts)
        IO.puts(Symphony.render(result))
        0

      ["tui" | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest, validate_provider: true),
             :ok <- normalize_tui_result(TUI.start(opts)) do
          0
        else
          {:error, message} ->
            IO.puts(message)
            1
        end

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

      ["load-session", session_ref | rest] ->
        with {:ok, opts, _args} <- parse_opts(rest),
             {:ok, session_id} <- expand_session_ref(session_ref, opts),
             {:ok, session} <- SessionStore.fetch(session_id, root: session_root_opt(opts)) do
          emit_value(session, opts, fn -> render_session(session, opts) end)
          0
        else
          :error ->
            emit_error("Session not found: #{session_ref}", json_requested?(rest))
            1

          {:error, :not_found} ->
            emit_error("Session not found: #{session_ref}", json_requested?(rest))
            1

          {:error, {:invalid_session, _details} = reason} ->
            emit_error(session_store_error(reason), json_requested?(rest))
            1

          {:error, message} ->
            emit_error(message, json_requested?(rest))
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
      render_chat_vision_backbone(result.vision_backbone),
      render_chat_permissions(result.permissions),
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
        summary = session_summary(session)

        [
          summary.id,
          summary.updated_at,
          "run=#{summary.run_status}",
          "stop=#{summary.stop_reason}",
          "provider=#{summary.provider}",
          "messages=#{summary.message_count}",
          "receipts=#{summary.receipt_count}",
          "output=#{summary.output_summary}"
        ]
        |> Enum.join("\t")
      end)
    ]
    |> Enum.join("\n")
  end

  defp session_summary(session) do
    %{
      id: session["id"],
      updated_at: session["updated_at"] || session["saved_at"] || "unknown",
      stop_reason: session["stop_reason"] || "unknown",
      run_status: get_in(session, ["run_state", "status"]) || "unknown",
      provider: session_provider(session),
      message_count: length(session["messages"] || []),
      receipt_count: length(session["tool_receipts"] || []),
      output_summary: summarize_text(session["output"] || "-")
    }
  end

  defp render_session(session, opts) do
    requirements = session["requirements"] || []
    tool_receipts = session["tool_receipts"] || []
    messages = session["messages"] || []
    run_state = session["run_state"] || %{}

    [
      session["id"],
      "created=#{session["created_at"] || session["saved_at"]}",
      "updated=#{session["updated_at"] || session["saved_at"]}",
      "provider=#{session_provider(session)}",
      "model=#{get_in(session, ["provider", "model"]) || "-"}",
      render_session_vision_backbone(session),
      render_session_permissions(session),
      "#{length(messages)} messages",
      "requirements=#{length(requirements)}",
      "tool_receipts=#{length(tool_receipts)}",
      "run=#{run_state["status"] || "unknown"}",
      "stop=#{session["stop_reason"]}",
      "started=#{run_state["started_at"] || "-"}",
      "finished=#{run_state["finished_at"] || "-"}",
      "last_stop=#{run_state["last_stop_reason"] || session["stop_reason"] || "-"}",
      "prompt=#{summarize_text(session["prompt"] || "-")}",
      "output=#{summarize_text(session["output"] || "-")}",
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
        content = message["content"] |> Multimodal.summary() |> summarize_text()
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

        [
          "#{index}. #{started_at} #{tool} status=#{status} exit=#{exit_status} output=#{output}",
          render_receipt_policy(receipt)
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")
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

    [
      "Last receipt: #{tool} #{status} #{duration_ms}ms #{summarize_text(invocation)}",
      render_receipt_policy(receipt)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp session_provider(session) do
    get_in(session, ["provider", "provider"]) || "unknown"
  end

  defp render_chat_vision_backbone(nil), do: nil

  defp render_chat_vision_backbone(backbone) do
    "Vision backbone: #{vision_backbone_label(backbone)}"
  end

  defp render_chat_permissions(nil), do: nil

  defp render_chat_permissions(permissions) do
    "Permissions: #{permission_label(permissions)}"
  end

  defp render_session_vision_backbone(session) do
    case get_in(session, ["provider", "vision_backbone"]) do
      nil -> nil
      backbone -> "vision=#{vision_backbone_label(backbone)}"
    end
  end

  defp render_session_permissions(session) do
    case session["permissions"] do
      nil -> nil
      permissions -> "permissions=#{permission_label(permissions)}"
    end
  end

  defp vision_backbone_label(%{"provider" => provider, "model" => model})
       when is_binary(provider) and provider != "" and is_binary(model) and model != "" do
    "#{provider}/#{model}"
  end

  defp vision_backbone_label(%{provider: provider, model: model})
       when is_binary(provider) and provider != "" and is_binary(model) and model != "" do
    "#{provider}/#{model}"
  end

  defp vision_backbone_label(%{"provider" => provider})
       when is_binary(provider) and provider != "",
       do: provider

  defp vision_backbone_label(%{provider: provider}) when is_binary(provider) and provider != "",
    do: provider

  defp vision_backbone_label(%{"model" => model}) when is_binary(model) and model != "",
    do: model

  defp vision_backbone_label(%{model: model}) when is_binary(model) and model != "", do: model
  defp vision_backbone_label(_backbone), do: "configured"

  defp permission_label(%{
         tool_policy: tool_policy,
         allow_shell: allow_shell,
         allow_write: allow_write
       }) do
    "tool_policy=#{tool_policy} shell=#{enabled_label(allow_shell)} write=#{enabled_label(allow_write)}"
  end

  defp permission_label(%{
         "tool_policy" => tool_policy,
         "allow_shell" => allow_shell,
         "allow_write" => allow_write
       }) do
    "tool_policy=#{tool_policy} shell=#{enabled_label(allow_shell)} write=#{enabled_label(allow_write)}"
  end

  defp permission_label(_permissions), do: "configured"

  defp render_receipt_policy(receipt) do
    case receipt[:policy] || receipt["policy"] do
      %{"rule" => "blocked_shell_prefix", "blocked_prefix" => prefix} ->
        "policy=blocked_shell_prefix:#{prefix}"

      %{rule: "blocked_shell_prefix", blocked_prefix: prefix} ->
        "policy=blocked_shell_prefix:#{prefix}"

      %{"rule" => rule} when is_binary(rule) ->
        "policy=#{rule}"

      %{rule: rule} when is_binary(rule) ->
        "policy=#{rule}"

      _other ->
        nil
    end
  end

  defp enabled_label(true), do: "enabled"
  defp enabled_label(false), do: "disabled"
  defp enabled_label(value), do: to_string(value)

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
    with :ok <- validate_session_state(opts) do
      if Keyword.get(opts, :daemon, false) do
        run_daemon_chat(prompt, opts)
      else
        result = Runtime.chat(prompt, opts)
        emit_value(result, opts, fn -> render_chat_result(result) end)
        chat_exit_code(result)
      end
    else
      {:error, reason} ->
        emit_error(session_store_error(reason), opts)
        1
    end
  end

  defp run_daemon(["start" | rest]) do
    with {:ok, opts, _args} <- parse_opts(rest),
         {:ok, status} <- normalize_daemon_result(Daemon.start_background(opts)) do
      emit_value(status, opts, fn -> render_daemon_status(status) end)
      0
    else
      {:error, message} ->
        emit_error(message, json_requested?(rest))
        1
    end
  end

  defp run_daemon(["serve" | rest]) do
    with {:ok, opts, _args} <- parse_opts(rest),
         :ok <- normalize_daemon_serve(Daemon.serve(opts)) do
      0
    else
      {:error, message} ->
        emit_error(message, json_requested?(rest))
        1
    end
  end

  defp run_daemon(["status" | rest]) do
    with {:ok, opts, _args} <- parse_opts(rest),
         {:ok, status} <- normalize_daemon_result(Daemon.status(opts)) do
      emit_value(status, opts, fn -> render_daemon_status(status) end)
      0
    else
      {:error, message} ->
        emit_error(message, json_requested?(rest))
        1
    end
  end

  defp run_daemon(["stop" | rest]) do
    with {:ok, opts, _args} <- parse_opts(rest),
         {:ok, result} <- normalize_daemon_result(Daemon.stop(opts)) do
      emit_value(result, opts, fn -> render_daemon_stop(result) end)
      0
    else
      {:error, message} ->
        emit_error(message, json_requested?(rest))
        1
    end
  end

  defp run_daemon(_rest) do
    IO.puts("Usage: claw_code daemon <start|serve|status|stop>")
    1
  end

  defp run_cancel(session_ref, rest) do
    with {:ok, opts, _args} <- parse_opts(rest),
         {:ok, session_id} <- expand_session_ref(session_ref, opts),
         :ok <- validate_session_state(Keyword.put(opts, :session_id, session_id)) do
      if Keyword.get(opts, :daemon, false) do
        run_daemon_cancel(session_id, opts)
      else
        run_local_cancel(session_id, opts)
      end
    else
      {:error, :not_found} ->
        emit_error("Session not found: #{session_ref}", json_requested?(rest))
        1

      {:error, {:invalid_session, _details} = reason} ->
        emit_error(session_store_error(reason), json_requested?(rest))
        1

      {:error, message} ->
        IO.puts(message)
        1
    end
  end

  defp run_local_cancel(session_id, opts) do
    with {:ok, _cancelled} <- normalize_cancel(Runtime.cancel(session_id, opts)) do
      emit_value(%{session_id: session_id, transport: "local", cancelled: true}, opts, fn ->
        "Cancelled session in this runtime: #{session_id}"
      end)

      0
    else
      {:error, :not_found} ->
        emit_error("Session not found: #{session_id}", opts)
        1

      {:error, :not_running} ->
        emit_error("Session is not running in this runtime: #{session_id}", opts)
        1

      {:error, {:invalid_session, _details} = reason} ->
        emit_error(session_store_error(reason), opts)
        1

      {:error, message} when is_binary(message) ->
        emit_error(message, opts)
        1
    end
  end

  defp run_daemon_cancel(session_id, opts) do
    case Daemon.cancel_session(session_id, opts) do
      {:ok, cancelled} ->
        emit_value(cancelled, opts, fn -> "Cancelled session via daemon: #{session_id}" end)
        0

      {:error, :not_found} ->
        emit_error("Session not found: #{session_id}", opts)
        1

      {:error, :session_not_running} ->
        emit_error("Session is not running in the daemon: #{session_id}", opts)
        1

      {:error, :not_running} ->
        emit_error("Daemon is not running.", opts)
        1

      {:error, message} when is_binary(message) ->
        emit_error(message, opts)
        1

      {:error, reason} ->
        emit_error("Daemon cancel failed: #{inspect(reason)}", opts)
        1
    end
  end

  defp run_daemon_chat(prompt, opts) do
    case Daemon.chat(prompt, opts) do
      {:ok, result} ->
        emit_value(result, opts, fn -> render_chat_result(result) end)
        chat_exit_code(result)

      {:error, :not_running} ->
        emit_error("Daemon is not running. Start it with `./claw_code daemon start`.", opts)
        1

      {:error, message} when is_binary(message) ->
        emit_error(message, opts)
        1

      {:error, reason} ->
        emit_error("Daemon chat failed: #{inspect(reason)}", opts)
        1
    end
  end

  defp render_daemon_status(status) do
    [
      "# Daemon",
      "",
      "- status: #{status["status"]}",
      render_status_field("root", status["root"]),
      render_status_field("session_root", status["session_root"]),
      render_status_field("host", status["host"]),
      render_status_field("port", status["port"]),
      render_status_field("pid", status["pid"]),
      render_status_field("started_at", status["started_at"]),
      render_status_field("server_time", status["server_time"]),
      render_status_field("version", status["version"]),
      render_status_field("already_running", status["already_running"])
      | daemon_health_lines(status["health"])
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp render_daemon_stop(result) do
    [
      "# Daemon",
      "",
      "- status: #{result["status"] || "stopped"}"
    ]
    |> Enum.join("\n")
  end

  defp render_status_field(_key, nil), do: nil
  defp render_status_field(key, value), do: "- #{key}: #{value}"

  defp daemon_health_lines(nil), do: []

  defp daemon_health_lines(health) when is_map(health) do
    counts = health["counts"] || %{}
    running = health["latest_running"]
    failed = health["latest_failed"]
    recovered = health["latest_recovered"]

    [
      "- health: #{Enum.join(health["signals"] || [], ", ")}",
      "- sessions: total=#{counts["total"] || 0} running=#{counts["running"] || 0} completed=#{counts["completed"] || 0} failed=#{counts["failed"] || 0} recovered=#{counts["recovered"] || 0} invalid=#{counts["invalid"] || 0}",
      render_health_session("latest_running", running),
      render_health_receipt("latest_running", running),
      render_health_session("latest_failed", failed),
      render_health_receipt("latest_failed", failed),
      render_health_session("latest_recovered", recovered),
      render_health_receipt("latest_recovered", recovered)
    ]
  end

  defp render_health_session(_label, nil), do: nil

  defp render_health_session(label, entry) do
    [
      "- #{label}: #{entry["id"]}",
      "provider=#{entry["provider"] || "unknown"}",
      "stop=#{entry["stop_reason"] || "unknown"}",
      "run=#{entry["run"] || entry["run_status"] || "unknown"}",
      "updated=#{entry["updated_at"] || "-"}",
      render_health_detail(entry["detail"])
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp render_health_receipt(_label, nil), do: nil
  defp render_health_receipt(_label, %{"last_receipt" => nil}), do: nil

  defp render_health_receipt(label, entry) do
    receipt = entry["last_receipt"]

    "- #{label}_receipt: #{receipt["tool"] || "unknown"} #{receipt["status"] || "unknown"} #{receipt["duration_ms"] || "-"}ms #{receipt["started_at"] || "-"}"
  end

  defp render_health_detail("-"), do: nil
  defp render_health_detail(detail), do: "detail=#{detail}"

  defp session_root_opt(opts) do
    Keyword.get(opts, :session_root, SessionStore.root_dir())
  end

  defp expand_session_ref(session_ref, opts) do
    if alias_or_index_session_ref?(session_ref) do
      case resolve_session_ref(session_ref, opts) do
        nil -> {:error, :not_found}
        resolved -> {:ok, resolved}
      end
    else
      {:ok, session_ref}
    end
  end

  defp alias_or_index_session_ref?(session_ref) do
    normalized = String.downcase(session_ref)

    normalized in [
      "latest",
      "running",
      "latest-running",
      "completed",
      "latest-completed",
      "failed",
      "latest-failed"
    ] or match?({_, ""}, Integer.parse(session_ref))
  end

  defp resolve_session_ref(session_ref, opts) do
    sessions =
      SessionStore.list(
        limit: max(Keyword.get(opts, :limit, 20), 100),
        root: session_root_opt(opts)
      )

    normalized = String.downcase(session_ref)

    case normalized do
      "latest" -> first_session_id(sessions)
      "running" -> first_matching_session_id(sessions, &session_running?/1)
      "latest-running" -> first_matching_session_id(sessions, &session_running?/1)
      "completed" -> first_matching_session_id(sessions, &session_completed?/1)
      "latest-completed" -> first_matching_session_id(sessions, &session_completed?/1)
      "failed" -> first_matching_session_id(sessions, &session_failed?/1)
      "latest-failed" -> first_matching_session_id(sessions, &session_failed?/1)
      _other -> resolve_session_index(session_ref, sessions)
    end
  end

  defp resolve_session_index(session_ref, sessions) do
    case Integer.parse(session_ref) do
      {index, ""} when index > 0 ->
        sessions
        |> Enum.at(index - 1)
        |> case do
          nil -> nil
          session -> session["id"]
        end

      _other ->
        nil
    end
  end

  defp first_session_id([session | _rest]), do: session["id"]
  defp first_session_id([]), do: nil

  defp first_matching_session_id(sessions, predicate) do
    sessions
    |> Enum.find(predicate)
    |> case do
      nil -> nil
      session -> session["id"]
    end
  end

  defp session_running?(session), do: get_in(session, ["run_state", "status"]) == "running"
  defp session_completed?(session), do: session["stop_reason"] == "completed"

  defp session_failed?(session) do
    not session_running?(session) and not session_completed?(session) and
      not is_nil(session["stop_reason"])
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
    vision_provider = opts[:vision_provider]

    cond do
      not OpenAICompatible.valid_provider?(provider) ->
        {:error,
         "Unknown provider: #{provider}. Expected one of: #{Enum.join(OpenAICompatible.providers(), ", ")}"}

      is_binary(vision_provider) and not OpenAICompatible.valid_provider?(vision_provider) ->
        {:error,
         "Unknown vision provider: #{vision_provider}. Expected one of: #{Enum.join(OpenAICompatible.providers(), ", ")}"}

      true ->
        {:ok, normalize_opts(opts), args}
    end
  end

  defp chat_exit_code(%{stop_reason: "completed"}), do: 0
  defp chat_exit_code(_result), do: 1

  defp normalize_daemon_result({:ok, status}), do: {:ok, status}
  defp normalize_daemon_result({:error, reason}), do: {:error, daemon_error_message(reason)}

  defp normalize_daemon_serve(:ok), do: :ok
  defp normalize_daemon_serve({:error, reason}), do: {:error, daemon_error_message(reason)}

  defp daemon_error_message(:not_running), do: "Daemon is not running."
  defp daemon_error_message(:already_running), do: "Daemon is already running."
  defp daemon_error_message(:session_not_running), do: "Session is not running in the daemon."
  defp daemon_error_message(:start_timeout), do: "Daemon did not become ready in time."
  defp daemon_error_message(:stop_timeout), do: "Daemon did not stop in time."

  defp daemon_error_message(:missing_executable) do
    "Daemon start needs a built escript. Run `mix escript.build` first."
  end

  defp daemon_error_message({:start_failed, status}) do
    "Daemon start failed with exit status #{status}."
  end

  defp daemon_error_message(reason) when is_binary(reason), do: reason
  defp daemon_error_message(reason), do: inspect(reason)

  defp normalize_tui_result(:ok), do: :ok
  defp normalize_tui_result({:error, reason}), do: {:error, daemon_error_message(reason)}

  defp normalize_cancel({:ok, {_path, document}}), do: {:ok, document}
  defp normalize_cancel({:error, :not_running}), do: {:error, :not_running}
  defp normalize_cancel({:error, :not_found}), do: {:error, :not_found}
  defp normalize_cancel(other), do: other

  defp validate_session_state(opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        :ok

      session_id ->
        case SessionStore.fetch(session_id, root: session_root_opt(opts)) do
          {:error, {:invalid_session, _details} = reason} -> {:error, reason}
          _other -> :ok
        end
    end
  end

  defp normalize_opts(opts) do
    opts
    |> normalize_inverse_flag(:tools, :no_tools)
    |> normalize_inverse_flag(:native, :no_native)
    |> normalize_inverse_flag(:daemon, :no_daemon)
  end

  defp normalize_inverse_flag(opts, key, inverse_key) do
    if Keyword.get(opts, inverse_key, false) do
      Keyword.put(opts, key, false)
    else
      opts
    end
  end

  defp emit_value(value, opts, renderer) do
    if Keyword.get(opts, :json, false) do
      IO.puts(render_json(value))
    else
      IO.puts(renderer.())
    end
  end

  defp emit_error(message, opts_or_flag) do
    if json_enabled?(opts_or_flag) do
      IO.puts(render_json(%{error: message}))
    else
      IO.puts(message)
    end
  end

  defp json_enabled?(flag) when is_boolean(flag), do: flag
  defp json_enabled?(opts) when is_list(opts), do: Keyword.get(opts, :json, false)

  defp json_requested?(args) do
    Enum.any?(args, &(&1 == "--json"))
  end

  defp render_json(value) do
    Jason.encode!(json_safe(value), pretty: true)
  end

  defp map_value(map, key, default \\ nil) when is_map(map) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key), default)) do
      nil -> default
      value -> value
    end
  end

  defp session_store_error({:invalid_session, _details} = reason),
    do: SessionStore.error_message(reason)

  defp session_store_error(reason) when is_binary(reason), do: reason
  defp session_store_error(reason), do: inspect(reason)

  defp json_safe(%_struct{} = struct), do: struct |> Map.from_struct() |> json_safe()

  defp json_safe(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), json_safe(value)}
      {key, value} -> {key, json_safe(value)}
    end)
  end

  defp json_safe(list) when is_list(list), do: Enum.map(list, &json_safe/1)
  defp json_safe(value), do: value

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

  defp render_probe(payload) do
    [
      "# Probe",
      "",
      "- status: #{map_value(payload, :status)}",
      "- provider: #{map_value(payload, :provider)}",
      "- configured: #{map_value(payload, :configured)}",
      "- auth_mode: #{map_value(payload, :auth_mode)}",
      "- tool_support: #{map_value(payload, :tool_support)}",
      "- input_modalities: #{render_missing_fields(map_value(payload, :input_modalities, []))}",
      "- request_modalities: #{render_missing_fields(map_value(payload, :request_modalities, []))}",
      "- payload_modes: #{Enum.join(map_value(payload, :payload_modes, []), ", ")}",
      "- fallback_modes: #{render_missing_fields(map_value(payload, :fallback_modes, []))}",
      "- provider_aliases: #{render_missing_fields(map_value(payload, :provider_aliases, []))}",
      "- request_url: #{map_value(payload, :request_url, "missing")}",
      "- model: #{map_value(payload, :model, "missing")}",
      "- request_mode: #{map_value(payload, :request_mode, "standard")}",
      if(map_value(payload, :latency_ms), do: "- latency_ms: #{map_value(payload, :latency_ms)}"),
      if(map_value(payload, :response_preview),
        do: "- response: #{summarize_text(map_value(payload, :response_preview))}"
      ),
      if(map_value(payload, :error), do: "- error: #{map_value(payload, :error)}"),
      "- missing: #{render_missing_fields(map_value(payload, :missing, []))}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp render_missing_fields([]), do: "none"
  defp render_missing_fields(fields), do: Enum.map_join(fields, ", ", &to_string/1)

  defp render_install(payload) do
    [
      "# Install",
      "",
      "- launcher: #{map_value(payload, :launcher)}",
      "- launcher_path: #{map_value(payload, :launcher_path)}",
      "- source: #{map_value(payload, :source)}",
      "- action: #{map_value(payload, :action)}",
      "- default_command: #{map_value(payload, :default_command)}",
      "- path_status: #{map_value(payload, :path_status)}",
      "- shell_snippet: #{map_value(payload, :shell_snippet)}"
    ]
    |> Enum.join("\n")
  end

  defp install_launcher(opts) do
    with {:ok, source} <- install_source_path(),
         {:ok, launcher} <- validate_launcher_name(Keyword.get(opts, :as, @default_launcher)),
         bin_dir <- install_bin_dir(opts),
         :ok <-
           normalize_file_result(File.mkdir_p(bin_dir), "Could not create bin dir: #{bin_dir}"),
         launcher_path <- Path.join(bin_dir, launcher),
         script <- launcher_script(source),
         {:ok, action} <- write_launcher(launcher_path, script, Keyword.get(opts, :force, false)) do
      {:ok,
       %{
         launcher: launcher,
         launcher_path: launcher_path,
         source: source,
         action: action,
         default_command: "tui",
         path_status: path_status(bin_dir),
         shell_snippet: shell_snippet(bin_dir)
       }}
    end
  end

  defp install_source_path do
    case install_source_candidates() |> Enum.find(&install_source?/1) do
      nil ->
        {:error,
         "Install needs a built escript. Run `mix escript.build` first or set `CLAW_INSTALL_SOURCE`."}

      source ->
        {:ok, Path.expand(source)}
    end
  end

  defp install_source_candidates do
    env_source =
      case System.get_env("CLAW_INSTALL_SOURCE") do
        value when is_binary(value) and value != "" -> [value]
        _other -> []
      end

    script_source =
      case safe_script_name() do
        value when is_binary(value) and value != "" -> [value]
        _other -> []
      end

    local_source =
      case File.cwd() do
        {:ok, cwd} -> [Path.join(cwd, "claw_code")]
        _other -> []
      end

    env_source ++ script_source ++ local_source
  end

  defp safe_script_name do
    case :escript.script_name() do
      [] -> nil
      value when is_list(value) -> List.to_string(value)
      value when is_binary(value) -> value
      _other -> nil
    end
  rescue
    _error -> nil
  end

  defp install_source?(path) when is_binary(path), do: File.regular?(path)
  defp install_source?(_path), do: false

  defp install_bin_dir(opts) do
    opts
    |> Keyword.get(:bin_dir, @default_bin_dir)
    |> Path.expand()
  end

  defp validate_launcher_name(name) when is_binary(name) do
    if name != "" and not String.contains?(name, ["/", "\\", " "]) do
      {:ok, name}
    else
      {:error, "Launcher name must be a single path-safe token without spaces or slashes."}
    end
  end

  defp validate_launcher_name(_name) do
    {:error, "Launcher name must be a single path-safe token without spaces or slashes."}
  end

  defp normalize_file_result(:ok, _message), do: :ok

  defp normalize_file_result({:error, reason}, message),
    do: {:error, "#{message}: #{inspect(reason)}"}

  defp launcher_script(source) do
    quoted_source = shell_double_quote(source)

    """
    #!/bin/sh
    set -eu

    if [ "$#" -eq 0 ]; then
      exec "#{quoted_source}" tui
    fi

    exec "#{quoted_source}" "$@"
    """
  end

  defp shell_double_quote(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end

  defp write_launcher(path, script, force?) do
    existed? = File.exists?(path)

    cond do
      existed? and not force? ->
        case File.read(path) do
          {:ok, ^script} ->
            {:ok, "unchanged"}

          _other ->
            {:error, "Launcher already exists: #{path}. Re-run with `--force` to replace it."}
        end

      true ->
        with :ok <-
               normalize_file_result(
                 File.write(path, script),
                 "Could not write launcher: #{path}"
               ),
             :ok <-
               normalize_file_result(File.chmod(path, 0o755), "Could not chmod launcher: #{path}") do
          {:ok, if(existed? and force?, do: "replaced", else: "installed")}
        end
    end
  end

  defp path_status(bin_dir) do
    expanded = Path.expand(bin_dir)

    System.get_env("PATH", "")
    |> String.split(":", trim: true)
    |> Enum.map(&Path.expand/1)
    |> Enum.member?(expanded)
    |> case do
      true -> "present"
      false -> "missing"
    end
  end

  defp shell_snippet(bin_dir) do
    "export PATH=\"#{bin_dir}:$PATH\""
  end

  defp help do
    """
    claw_code <command>

    Commands:
      summary
      manifest
      doctor [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--api-key-header HEADER] [--tools|--no-tools] [--json]
      providers [--json]
      install [--as NAME] [--bin-dir PATH] [--force] [--json]
      probe [prompt] [--image PATH]... [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--api-key-header HEADER] [--json]
      daemon serve [--daemon-root PATH] [--session-root PATH]
      daemon start [--daemon-root PATH] [--session-root PATH] [--json]
      daemon status [--daemon-root PATH] [--json]
      daemon stop [--daemon-root PATH] [--json]
      sessions [--limit N] [--query TEXT] [--session-root PATH] [--json]
      commands [--limit N] [--query TEXT]
      tools [--limit N] [--query TEXT] [--deny-tool NAME] [--deny-prefix PREFIX]
      route <prompt> [--limit N] [--native|--no-native]
      bootstrap <prompt> [--limit N] [--native|--no-native]
      chat <prompt> [--image PATH]... [--daemon] [--session-id ID] [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--api-key-header HEADER] [--vision-provider glm|nim|kimi|generic] [--vision-model MODEL] [--vision-base-url URL] [--vision-api-key KEY] [--vision-api-key-header HEADER] [--max-turns N] [--allow-shell] [--allow-write] [--tools|--no-tools] [--native|--no-native] [--session-root PATH] [--daemon-root PATH] [--json]
      resume-session <session_id|latest|running|latest-running|completed|latest-completed|failed|latest-failed|N> <prompt> [--image PATH]... [--daemon] [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--api-key-header HEADER] [--vision-provider glm|nim|kimi|generic] [--vision-model MODEL] [--vision-base-url URL] [--vision-api-key KEY] [--vision-api-key-header HEADER] [--max-turns N] [--allow-shell] [--allow-write] [--tools|--no-tools] [--native|--no-native] [--session-root PATH] [--daemon-root PATH] [--json]
      cancel-session <session_id|latest|running|latest-running|completed|latest-completed|failed|latest-failed|N> [--daemon] [--session-root PATH] [--daemon-root PATH] [--json]
      symphony <prompt> [--limit N] [--native|--no-native]
      tui [--limit N] [--provider glm|nim|kimi|generic] [--model MODEL] [--base-url URL] [--api-key KEY] [--api-key-header HEADER] [--tools|--no-tools] [--daemon-root PATH] [--session-root PATH]
      turn-loop <prompt> ...
      show-command <name>
      show-tool <name>
      exec-command <name> <prompt>
      exec-tool <name> <payload>
      load-session <session_id|latest|running|latest-running|completed|latest-completed|failed|latest-failed|N> [--session-root PATH] [--show-messages] [--show-receipts] [--json]
    """
  end
end
