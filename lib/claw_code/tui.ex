defmodule ClawCode.TUI do
  alias ClawCode.{Daemon, Manifest, SessionStore}
  alias ClawCode.Providers.OpenAICompatible

  defmodule State do
    @enforce_keys [:opts]
    defstruct opts: [],
              daemon_status: %{},
              doctor: %{},
              all_sessions: [],
              sessions: [],
              session_filter: :all,
              session_query: nil,
              session_limit: 8,
              session_root: nil,
              watch_interval_ms: nil,
              transcript_query: nil,
              transcript_match_index: 0,
              selected_session_id: nil,
              selected_session: nil,
              notice: nil
  end

  def start(opts \\ []) do
    with {:ok, daemon_status, notice} <- ensure_daemon(opts) do
      opts
      |> build_state(daemon_status, notice)
      |> loop()
    end
  end

  def build_state(opts, daemon_status, notice \\ nil, ui \\ %{}) do
    session_root =
      daemon_status["session_root"] || Keyword.get(opts, :session_root, SessionStore.root_dir())

    session_limit = Map.get(ui, :session_limit, Keyword.get(opts, :limit, 8))
    session_filter = Map.get(ui, :session_filter, :all)

    session_query =
      normalize_session_query(Map.get(ui, :session_query, Keyword.get(opts, :query)))

    watch_interval_ms = normalize_watch_interval(Map.get(ui, :watch_interval_ms))
    transcript_query = normalize_transcript_query(Map.get(ui, :transcript_query))
    transcript_match_index = Map.get(ui, :transcript_match_index, 0)

    all_sessions = SessionStore.list(limit: session_limit, root: session_root)
    sessions = all_sessions |> filter_sessions(session_filter) |> search_sessions(session_query)
    selected_session_id = default_selected_session_id(sessions)
    selected_session = fetch_session(selected_session_id, session_root)

    %State{
      opts: opts,
      daemon_status: daemon_status,
      doctor: Manifest.doctor_payload(opts),
      all_sessions: all_sessions,
      sessions: sessions,
      session_filter: session_filter,
      session_query: session_query,
      session_limit: session_limit,
      session_root: session_root,
      watch_interval_ms: watch_interval_ms,
      transcript_query: transcript_query,
      transcript_match_index: transcript_match_index,
      selected_session_id: selected_session_id,
      selected_session: selected_session,
      notice: notice
    }
    |> normalize_transcript_state()
  end

  def apply_command(%State{} = state, input) when is_binary(input) do
    case String.trim(input) do
      "" ->
        refresh(state, nil)

      "q" ->
        {:halt, state}

      "quit" ->
        {:halt, state}

      "exit" ->
        {:halt, state}

      "refresh" ->
        refresh(state, "Refreshed.")

      "r" ->
        refresh(state, "Refreshed.")

      "probe" ->
        probe_provider(state)

      "help" ->
        {:continue, %{state | notice: help_text()}}

      "cancel" ->
        cancel_selected(state)

      <<"filter ", filter::binary>> ->
        set_session_filter(state, filter)

      "clear find" ->
        clear_session_query(state)

      <<"find ", query::binary>> ->
        set_session_query(state, query)

      <<"watch ", value::binary>> ->
        set_watch_interval(state, value)

      "clear find-msg" ->
        clear_transcript_query(state)

      <<"find-msg ", query::binary>> ->
        set_transcript_query(state, query)

      "next-hit" ->
        step_transcript_match(state, 1)

      "prev-hit" ->
        step_transcript_match(state, -1)

      <<"limit ", limit::binary>> ->
        set_session_limit(state, limit)

      "next" ->
        step_session(state, 1)

      "prev" ->
        step_session(state, -1)

      <<"open ", rest::binary>> ->
        open_session(state, rest)

      <<"chat ", prompt::binary>> ->
        send_chat(state, prompt, false)

      <<"resume ", value::binary>> ->
        resume_chat(state, value)

      <<"provider ", provider::binary>> ->
        set_provider(state, provider)

      <<"model ", model::binary>> ->
        set_model(state, model)

      <<"base-url ", base_url::binary>> ->
        set_base_url(state, base_url)

      "clear base-url" ->
        clear_base_url(state)

      <<"tools ", mode::binary>> ->
        set_tool_mode(state, mode)

      other ->
        {:continue, %{state | notice: "Unknown command: #{other}. Type `help`."}}
    end
  end

  def render(%State{} = state) do
    [
      "# Claw Code TUI",
      "",
      "daemon=#{state.daemon_status["status"] || "unknown"} provider=#{state.doctor[:provider] || "unknown"} model=#{nested_value(state.doctor, [:model, :value]) || "missing"} tools=#{state.doctor[:tool_policy] || :auto}",
      "base_url=#{nested_value(state.doctor, [:base_url, :value]) || "missing"} selected=#{selected_session_position(state)}",
      "runs=running:#{count_sessions(state.all_sessions, &session_running?/1)} completed:#{count_sessions(state.all_sessions, &session_completed?/1)} failed:#{count_sessions(state.all_sessions, &session_failed?/1)}",
      "sessions=#{length(state.sessions)}/#{length(state.all_sessions)} filter=#{state.session_filter} limit=#{state.session_limit} query=#{state.session_query || "-"}",
      "watch=#{watch_label(state.watch_interval_ms)}",
      "transcript_query=#{state.transcript_query || "-"} hit=#{selected_transcript_hit_position(state)}",
      "selected_run=#{selected_run_summary(state.selected_session)}",
      "selected_receipt=#{selected_receipt_summary(state.selected_session)}",
      "session_root=#{state.session_root}",
      if(state.notice, do: "notice=#{state.notice}"),
      "",
      "## Sessions",
      render_sessions(state.sessions, state.selected_session_id),
      "",
      "## Selected",
      render_selected_session(state),
      "",
      "## Commands",
      "chat <prompt> | resume <prompt> | resume <n|id|latest|running|completed|failed> <prompt> | open <n|id|latest|latest-running|latest-completed|running|completed|failed> | filter <all|running|completed|failed> | find <substring> | clear find | watch <seconds|on|off> | find-msg <substring> | clear find-msg | next-hit | prev-hit | limit <n> | next | prev | cancel | provider <name|default> | model <name|default> | base-url <url> | clear base-url | tools auto|on|off | probe | refresh | help | quit"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp loop(%State{} = state) do
    input_reader = spawn_input_reader()
    loop(state, input_reader)
  end

  defp loop(%State{} = state, input_reader) do
    IO.write(IO.ANSI.home() <> IO.ANSI.clear())
    IO.puts(render(state))
    IO.write("\nclaw> ")

    case next_loop_event(input_reader, state.watch_interval_ms) do
      {:input, nil} ->
        :ok

      {:input, input} ->
        case apply_command(state, input) do
          {:continue, next_state} -> loop(next_state, input_reader)
          {:halt, _state} -> :ok
        end

      :timeout ->
        {:continue, next_state} = refresh(state, nil)
        loop(next_state, input_reader)
    end
  end

  defp ensure_daemon(opts) do
    case Daemon.status(opts) do
      {:ok, %{"status" => "running"} = status} ->
        {:ok, status, "Connected to daemon."}

      {:ok, %{"status" => "stale"}} ->
        start_daemon(opts, "Replaced stale daemon metadata.")

      {:ok, %{"status" => "stopped"}} ->
        start_daemon(opts, "Started daemon for TUI.")
    end
  end

  defp start_daemon(opts, notice) do
    case Daemon.start_background(opts) do
      {:ok, status} -> {:ok, status, notice}
      {:error, reason} -> {:error, reason}
    end
  end

  defp refresh(%State{} = state, notice) do
    next_state =
      state.opts
      |> build_state(refresh_daemon_status(state), notice, ui_state(state))
      |> preserve_selection(state.selected_session_id)
      |> normalize_transcript_state()

    {:continue, next_state}
  end

  defp preserve_selection(%State{} = state, nil), do: state

  defp preserve_selection(%State{} = state, selected_session_id) do
    resolved_session_id =
      if Enum.any?(state.sessions, &(&1["id"] == selected_session_id)) do
        selected_session_id
      else
        default_selected_session_id(state.sessions)
      end

    selected_session = fetch_session(resolved_session_id, state.session_root)

    %{
      state
      | selected_session_id: resolved_session_id,
        selected_session: selected_session || state.selected_session
    }
  end

  defp refresh_daemon_status(%State{
         opts: opts,
         session_root: session_root,
         daemon_status: daemon_status
       }) do
    {:ok, status} = Daemon.status(opts)

    status
    |> Map.put_new("session_root", daemon_status["session_root"] || session_root)
  end

  defp open_session(%State{} = state, value) do
    case resolve_session_id(String.trim(value), state.sessions, state.all_sessions) do
      nil ->
        {:continue, %{state | notice: "Session not found: #{String.trim(value)}"}}

      session_id ->
        selected_session = fetch_session(session_id, state.session_root)

        {:continue,
         normalize_transcript_state(%{
           state
           | selected_session_id: session_id,
             selected_session: selected_session,
             notice: "Opened session #{session_id}."
         })}
    end
  end

  defp send_chat(%State{} = state, prompt, resume?) do
    send_chat(state, prompt, resume?, nil)
  end

  defp send_chat(%State{} = state, prompt, resume?, resume_session_id) do
    prompt = String.trim(prompt)
    target_session_id = if(resume?, do: resume_session_id || state.selected_session_id)

    cond do
      prompt == "" ->
        {:continue, %{state | notice: "Prompt is required."}}

      resume? and is_nil(target_session_id) ->
        {:continue, %{state | notice: "No session selected."}}

      true ->
        chat_opts =
          if resume? do
            Keyword.put(state.opts, :session_id, target_session_id)
          else
            state.opts
          end

        case Daemon.chat(prompt, chat_opts) do
          {:ok, result} ->
            refresh(
              %{state | selected_session_id: result.session_id},
              "Completed #{result.stop_reason} for #{result.session_id}."
            )

          {:error, reason} ->
            {:continue, %{state | notice: "Chat failed: #{format_reason(reason)}"}}
        end
    end
  end

  defp resume_chat(%State{} = state, value) do
    value = String.trim(value)

    case String.split(value, ~r/\s+/, parts: 2, trim: true) do
      [target, prompt] ->
        case resolve_session_id(target, state.sessions, state.all_sessions) do
          nil ->
            send_chat(state, value, true)

          session_id ->
            send_chat(%{state | selected_session_id: session_id}, prompt, true, session_id)
        end

      [target] ->
        case resolve_session_id(target, state.sessions, state.all_sessions) do
          nil -> send_chat(state, target, true)
          _session_id -> {:continue, %{state | notice: "Prompt is required."}}
        end

      [] ->
        {:continue, %{state | notice: "Prompt is required."}}
    end
  end

  defp cancel_selected(%State{selected_session_id: nil} = state) do
    {:continue, %{state | notice: "No session selected."}}
  end

  defp cancel_selected(%State{} = state) do
    case Daemon.cancel_session(state.selected_session_id, state.opts) do
      {:ok, _result} ->
        refresh(state, "Cancelled #{state.selected_session_id}.")

      {:error, reason} ->
        {:continue, %{state | notice: "Cancel failed: #{format_reason(reason)}"}}
    end
  end

  defp set_tool_mode(%State{} = state, value) do
    case String.trim(String.downcase(value)) do
      "auto" ->
        opts = Keyword.delete(state.opts, :tools)
        rebuild_with_opts(state, opts, "Tool policy set to auto.")

      "on" ->
        rebuild_with_opts(
          state,
          Keyword.put(state.opts, :tools, true),
          "Tool policy set to enabled."
        )

      "off" ->
        rebuild_with_opts(
          state,
          Keyword.put(state.opts, :tools, false),
          "Tool policy set to disabled."
        )

      other ->
        {:continue, %{state | notice: "Unknown tool mode: #{other}"}}
    end
  end

  defp set_provider(%State{} = state, value) do
    provider =
      value
      |> String.trim()
      |> String.downcase()

    cond do
      provider in ["", "default"] ->
        rebuild_with_opts(
          state,
          Keyword.delete(state.opts, :provider),
          "Provider reset to default."
        )

      OpenAICompatible.valid_provider?(provider) ->
        rebuild_with_opts(
          state,
          Keyword.put(state.opts, :provider, provider),
          "Provider set to #{provider}."
        )

      true ->
        {:continue, %{state | notice: "Unknown provider: #{provider}"}}
    end
  end

  defp set_model(%State{} = state, value) do
    model = String.trim(value)

    cond do
      model in ["", "default"] ->
        rebuild_with_opts(state, Keyword.delete(state.opts, :model), "Model reset to default.")

      true ->
        rebuild_with_opts(state, Keyword.put(state.opts, :model, model), "Model set to #{model}.")
    end
  end

  defp set_base_url(%State{} = state, value) do
    base_url = String.trim(value)

    if base_url == "" do
      {:continue, %{state | notice: "Base URL is required."}}
    else
      rebuild_with_opts(
        state,
        Keyword.put(state.opts, :base_url, base_url),
        "Base URL set to #{base_url}."
      )
    end
  end

  defp clear_base_url(%State{} = state) do
    rebuild_with_opts(state, Keyword.delete(state.opts, :base_url), "Base URL cleared.")
  end

  defp probe_provider(%State{} = state) do
    notice =
      case OpenAICompatible.probe(state.opts) do
        {:ok, payload} ->
          "Probe ok in #{payload.latency_ms}ms: #{summarize(payload.response_preview)}"

        {:error, payload} ->
          "Probe #{payload.status}: #{payload.error}"
      end

    rebuild_with_opts(state, state.opts, notice)
  end

  defp set_session_filter(%State{} = state, value) do
    case normalize_session_filter(value) do
      nil ->
        {:continue, %{state | notice: "Unknown filter: #{String.trim(value)}"}}

      session_filter ->
        next_state =
          state.opts
          |> build_state(
            refresh_daemon_status(state),
            "Filter set to #{session_filter}.",
            %{ui_state(state) | session_filter: session_filter}
          )
          |> preserve_selection(state.selected_session_id)

        {:continue, next_state}
    end
  end

  defp set_session_limit(%State{} = state, value) do
    case Integer.parse(String.trim(value)) do
      {session_limit, ""} when session_limit > 0 ->
        next_state =
          state.opts
          |> build_state(
            refresh_daemon_status(state),
            "Session limit set to #{session_limit}.",
            %{ui_state(state) | session_limit: session_limit}
          )
          |> preserve_selection(state.selected_session_id)

        {:continue, next_state}

      _other ->
        {:continue, %{state | notice: "Limit must be a positive integer."}}
    end
  end

  defp set_session_query(%State{} = state, value) do
    session_query = normalize_session_query(value)

    if is_nil(session_query) do
      {:continue, %{state | notice: "Search text is required."}}
    else
      next_state =
        state.opts
        |> build_state(
          refresh_daemon_status(state),
          "Find set to #{session_query}.",
          %{ui_state(state) | session_query: session_query}
        )
        |> preserve_selection(state.selected_session_id)

      {:continue, next_state}
    end
  end

  defp clear_session_query(%State{} = state) do
    next_state =
      state.opts
      |> build_state(
        refresh_daemon_status(state),
        "Find cleared.",
        %{ui_state(state) | session_query: nil}
      )
      |> preserve_selection(state.selected_session_id)

    {:continue, next_state}
  end

  defp set_watch_interval(%State{} = state, value) do
    case parse_watch_value(value) do
      {:ok, watch_interval_ms, notice} ->
        next_state =
          %{state | watch_interval_ms: watch_interval_ms, notice: notice}
          |> normalize_transcript_state()

        {:continue, next_state}

      {:error, message} ->
        {:continue, %{state | notice: message}}
    end
  end

  defp set_transcript_query(%State{} = state, value) do
    transcript_query = normalize_transcript_query(value)

    if is_nil(transcript_query) do
      {:continue, %{state | notice: "Transcript search text is required."}}
    else
      next_state =
        state
        |> Map.put(:transcript_query, transcript_query)
        |> Map.put(:transcript_match_index, 0)
        |> normalize_transcript_state()

      {:continue, %{next_state | notice: transcript_notice(transcript_query, next_state)}}
    end
  end

  defp clear_transcript_query(%State{} = state) do
    {:continue,
     %{
       state
       | transcript_query: nil,
         transcript_match_index: 0,
         notice: "Transcript find cleared."
     }}
  end

  defp step_transcript_match(%State{} = state, offset) do
    cond do
      is_nil(state.transcript_query) ->
        {:continue, %{state | notice: "Transcript search is not active."}}

      true ->
        match_count = transcript_match_count(state.selected_session, state.transcript_query)

        cond do
          match_count == 0 ->
            {:continue, %{state | notice: "No transcript matches for #{state.transcript_query}."}}

          true ->
            next_index = state.transcript_match_index + offset

            cond do
              next_index < 0 ->
                {:continue, %{state | notice: "Already at the first transcript hit."}}

              next_index >= match_count ->
                {:continue, %{state | notice: "Already at the last transcript hit."}}

              true ->
                next_state =
                  %{state | transcript_match_index: next_index}
                  |> normalize_transcript_state()

                {:continue,
                 %{next_state | notice: "Transcript hit #{next_index + 1}/#{match_count}."}}
            end
        end
    end
  end

  defp rebuild_with_opts(%State{} = state, opts, notice) do
    next_state =
      opts
      |> build_state(refresh_daemon_status(%{state | opts: opts}), notice, ui_state(state))
      |> preserve_selection(state.selected_session_id)
      |> normalize_transcript_state()

    {:continue, next_state}
  end

  defp ui_state(%State{} = state) do
    %{
      session_filter: state.session_filter || :all,
      session_query: state.session_query,
      session_limit: state.session_limit || 8,
      watch_interval_ms: state.watch_interval_ms,
      transcript_query: state.transcript_query,
      transcript_match_index: state.transcript_match_index || 0
    }
  end

  defp default_selected_session_id([session | _rest]), do: session["id"]
  defp default_selected_session_id([]), do: nil

  defp fetch_session(nil, _root), do: nil

  defp fetch_session(session_id, root) do
    case SessionStore.fetch(session_id, root: root) do
      {:ok, session} -> session
      :error -> nil
    end
  end

  defp resolve_session_id(value, sessions, all_sessions) do
    normalized = String.downcase(value)

    case normalized do
      "latest" ->
        first_session_id(all_sessions)

      "running" ->
        first_matching_session_id(all_sessions, &session_running?/1)

      "latest-running" ->
        first_matching_session_id(all_sessions, &session_running?/1)

      "completed" ->
        first_matching_session_id(all_sessions, &session_completed?/1)

      "latest-completed" ->
        first_matching_session_id(all_sessions, &session_completed?/1)

      "failed" ->
        first_matching_session_id(all_sessions, &session_failed?/1)

      "latest-failed" ->
        first_matching_session_id(all_sessions, &session_failed?/1)

      _other ->
        resolve_index_or_id(value, sessions)
    end
  end

  defp resolve_index_or_id(value, sessions) do
    case Integer.parse(value) do
      {index, ""} ->
        sessions
        |> Enum.at(index - 1)
        |> case do
          nil -> nil
          session -> session["id"]
        end

      _other ->
        if Enum.any?(sessions, &(&1["id"] == value)), do: value, else: nil
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

  defp filter_sessions(sessions, :all), do: sessions
  defp filter_sessions(sessions, :running), do: Enum.filter(sessions, &session_running?/1)
  defp filter_sessions(sessions, :completed), do: Enum.filter(sessions, &session_completed?/1)
  defp filter_sessions(sessions, :failed), do: Enum.filter(sessions, &session_failed?/1)

  defp search_sessions(sessions, nil), do: sessions

  defp search_sessions(sessions, query) do
    normalized_query = String.downcase(query)

    Enum.filter(sessions, fn session ->
      session
      |> session_search_text()
      |> String.contains?(normalized_query)
    end)
  end

  defp render_sessions([], _selected_session_id), do: "none"

  defp render_sessions(sessions, selected_session_id) do
    sessions
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {session, index} ->
      marker = if session["id"] == selected_session_id, do: ">", else: " "
      updated_at = session["updated_at"] || session["saved_at"] || "unknown"
      run_status = get_in(session, ["run_state", "status"]) || "unknown"
      stop_reason = session["stop_reason"] || "unknown"
      messages = length(session["messages"] || [])
      receipts = length(session["tool_receipts"] || [])

      "#{marker} #{index}. #{session["id"]} #{updated_at} run=#{run_status} stop=#{stop_reason} messages=#{messages} receipts=#{receipts}"
    end)
  end

  defp render_selected_session(%State{selected_session: nil}), do: "none"

  defp render_selected_session(%State{} = state) do
    session = state.selected_session

    [
      "id=#{session["id"]}",
      "stop=#{session["stop_reason"] || "unknown"} run=#{get_in(session, ["run_state", "status"]) || "unknown"} turns=#{session["turns"] || 0}",
      render_run_metadata(session),
      render_last_receipt_summary(session),
      "messages:",
      render_messages(
        session["messages"] || [],
        state.transcript_query,
        state.transcript_match_index
      ),
      "receipts:",
      render_receipts(session["tool_receipts"] || [])
    ]
    |> Enum.join("\n")
  end

  defp render_messages([], _query, _match_index), do: "  none"

  defp render_messages(messages, nil, _match_index) do
    messages
    |> Enum.take(-6)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {message, index} ->
      role = message["role"] || "unknown"
      content = summarize(message["content"])
      "  #{index}. #{role}: #{content}"
    end)
  end

  defp render_messages(messages, query, match_index) do
    matches = transcript_matches(messages, query)

    case matches do
      [] ->
        "  no matches for #{inspect(query)}"

      _present ->
        {_message, message_index} = Enum.at(matches, match_index)
        start_index = max(message_index - 1, 0)
        end_index = min(message_index + 1, length(messages) - 1)

        visible_messages =
          messages
          |> Enum.with_index()
          |> Enum.filter(fn {_message, index} -> index >= start_index and index <= end_index end)

        [
          "  match #{match_index + 1}/#{length(matches)} for #{inspect(query)}",
          Enum.map_join(visible_messages, "\n", fn {message, index} ->
            role = message["role"] || "unknown"
            content = summarize(message["content"])
            marker = if index == message_index, do: ">", else: " "
            " #{marker} #{index + 1}. #{role}: #{content}"
          end)
        ]
        |> Enum.join("\n")
    end
  end

  defp render_receipts([]), do: "  none"

  defp render_receipts(receipts) do
    receipts
    |> Enum.take(-4)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {receipt, index} ->
      tool = receipt["tool_name"] || receipt[:tool_name] || receipt["tool"] || "unknown"
      status = receipt["status"] || receipt[:status] || "unknown"
      duration_ms = receipt["duration_ms"] || receipt[:duration_ms] || "-"
      started_at = receipt["started_at"] || receipt[:started_at] || "-"
      "  #{index}. #{tool} #{status} #{duration_ms}ms #{started_at}"
    end)
  end

  defp render_run_metadata(session) do
    run_state = session["run_state"] || %{}
    started_at = run_state["started_at"] || "-"
    finished_at = run_state["finished_at"] || "-"
    last_stop_reason = run_state["last_stop_reason"] || session["stop_reason"] || "-"
    "started=#{started_at} finished=#{finished_at} last_stop=#{last_stop_reason}"
  end

  defp render_last_receipt_summary(session) do
    case last_receipt(session) do
      nil ->
        "last_receipt=none"

      receipt ->
        tool =
          receipt["tool_name"] || receipt[:tool_name] || receipt["tool"] || receipt[:tool] ||
            receipt["command"] || receipt[:command] || "unknown"

        status = receipt["status"] || receipt[:status] || "unknown"
        duration_ms = receipt["duration_ms"] || receipt[:duration_ms] || "-"
        started_at = receipt["started_at"] || receipt[:started_at] || "-"
        "last_receipt=#{tool} #{status} #{duration_ms}ms #{started_at}"
    end
  end

  defp help_text do
    "Commands: chat <prompt>, resume <prompt>, resume <n|id|latest|running|completed|failed> <prompt>, open <n|id|latest|latest-running|latest-completed|running|completed|failed>, filter <all|running|completed|failed>, find <substring>, clear find, watch <seconds|on|off>, find-msg <substring>, clear find-msg, next-hit, prev-hit, limit <n>, next, prev, cancel, provider <name|default>, model <name|default>, base-url <url>, clear base-url, tools auto|on|off, probe, refresh, help, quit"
  end

  defp step_session(%State{sessions: []} = state, _offset) do
    {:continue, %{state | notice: "No sessions available."}}
  end

  defp step_session(%State{} = state, offset) do
    current_index =
      state.sessions
      |> Enum.find_index(&(&1["id"] == state.selected_session_id))
      |> Kernel.||(0)

    next_index = current_index + offset

    cond do
      next_index < 0 ->
        {:continue, %{state | notice: "Already at the first session."}}

      next_index >= length(state.sessions) ->
        {:continue, %{state | notice: "Already at the last session."}}

      true ->
        session = Enum.at(state.sessions, next_index)
        open_session(state, session["id"])
    end
  end

  defp selected_session_position(%State{sessions: []}), do: "none"

  defp selected_session_position(%State{} = state) do
    case Enum.find_index(state.sessions, &(&1["id"] == state.selected_session_id)) do
      nil -> "none"
      index -> "#{index + 1}/#{length(state.sessions)}"
    end
  end

  defp count_sessions(sessions, predicate) do
    Enum.count(sessions, predicate)
  end

  defp selected_run_summary(nil), do: "none"

  defp selected_run_summary(session) do
    run_state = session["run_state"] || %{}
    status = run_state["status"] || "unknown"

    case status do
      "running" -> "running since=#{run_state["started_at"] || "-"}"
      _other -> "idle last_stop=#{run_state["last_stop_reason"] || session["stop_reason"] || "-"}"
    end
  end

  defp selected_receipt_summary(nil), do: "none"

  defp selected_receipt_summary(session) do
    case last_receipt(session) do
      nil ->
        "none"

      receipt ->
        tool =
          receipt["tool_name"] || receipt[:tool_name] || receipt["tool"] || receipt[:tool] ||
            receipt["command"] || receipt[:command] || "unknown"

        status = receipt["status"] || receipt[:status] || "unknown"
        duration_ms = receipt["duration_ms"] || receipt[:duration_ms] || "-"
        "#{tool}:#{status}:#{duration_ms}ms"
    end
  end

  defp nested_value(map, keys) when is_map(map) do
    get_in(map, keys)
  end

  defp nested_value(_value, _keys), do: nil

  defp normalize_session_filter(value) do
    case String.trim(String.downcase(value)) do
      "all" -> :all
      "running" -> :running
      "completed" -> :completed
      "failed" -> :failed
      _other -> nil
    end
  end

  defp normalize_session_query(nil), do: nil

  defp normalize_session_query(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      query -> query
    end
  end

  defp normalize_watch_interval(nil), do: nil

  defp normalize_watch_interval(value) when is_integer(value) and value > 0, do: value
  defp normalize_watch_interval(_value), do: nil

  defp parse_watch_value(value) do
    case String.trim(String.downcase(value)) do
      "" ->
        {:error, "Watch interval is required."}

      "off" ->
        {:ok, nil, "Watch disabled."}

      "on" ->
        {:ok, 2_000, "Watch enabled at 2s."}

      seconds ->
        case Integer.parse(seconds) do
          {parsed, ""} when parsed > 0 ->
            {:ok, parsed * 1_000, "Watch enabled at #{parsed}s."}

          _other ->
            {:error, "Watch interval must be `on`, `off`, or a positive integer."}
        end
    end
  end

  defp watch_label(nil), do: "off"
  defp watch_label(interval_ms), do: "#{div(interval_ms, 1_000)}s"

  defp normalize_transcript_query(nil), do: nil

  defp normalize_transcript_query(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      query -> query
    end
  end

  defp normalize_transcript_state(%State{transcript_query: nil} = state) do
    %{state | transcript_match_index: 0}
  end

  defp normalize_transcript_state(%State{} = state) do
    match_count = transcript_match_count(state.selected_session, state.transcript_query)

    cond do
      match_count == 0 ->
        %{state | transcript_match_index: 0}

      state.transcript_match_index < 0 ->
        %{state | transcript_match_index: 0}

      state.transcript_match_index >= match_count ->
        %{state | transcript_match_index: match_count - 1}

      true ->
        state
    end
  end

  defp selected_transcript_hit_position(%State{transcript_query: nil}), do: "-"

  defp selected_transcript_hit_position(%State{} = state) do
    match_count = transcript_match_count(state.selected_session, state.transcript_query)

    if match_count == 0 do
      "0/0"
    else
      "#{state.transcript_match_index + 1}/#{match_count}"
    end
  end

  defp session_running?(session) do
    get_in(session, ["run_state", "status"]) == "running"
  end

  defp session_completed?(session) do
    session["stop_reason"] == "completed"
  end

  defp session_failed?(session) do
    not session_running?(session) and not session_completed?(session) and
      not is_nil(session["stop_reason"])
  end

  defp session_search_text(session) do
    [
      session["id"],
      session["prompt"],
      session["output"],
      session["stop_reason"],
      get_in(session, ["provider", "provider"]),
      Enum.map_join(session["messages"] || [], "\n", &message_search_text/1)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> String.downcase()
  end

  defp message_search_text(%{"content" => content}) when is_binary(content), do: content
  defp message_search_text(%{"role" => role}) when is_binary(role), do: role
  defp message_search_text(_message), do: ""

  defp transcript_match_count(nil, _query), do: 0
  defp transcript_match_count(_session, nil), do: 0

  defp transcript_match_count(session, query) do
    session["messages"]
    |> List.wrap()
    |> transcript_matches(query)
    |> length()
  end

  defp transcript_matches(messages, query) do
    normalized_query = String.downcase(query)

    messages
    |> Enum.with_index()
    |> Enum.filter(fn {message, _index} ->
      message
      |> message_search_text()
      |> String.downcase()
      |> String.contains?(normalized_query)
    end)
  end

  defp transcript_notice(query, %State{} = state) do
    match_count = transcript_match_count(state.selected_session, query)

    if match_count == 0 do
      "Transcript find set to #{query}. No matches."
    else
      "Transcript find set to #{query}. Hit 1/#{match_count}."
    end
  end

  defp last_receipt(nil), do: nil

  defp last_receipt(session) do
    session
    |> Map.get("tool_receipts", [])
    |> List.last()
  end

  defp spawn_input_reader do
    parent = self()

    spawn_link(fn ->
      input_reader_loop(parent)
    end)
  end

  defp input_reader_loop(parent) do
    case IO.gets("") do
      nil ->
        send(parent, {:tui_input, nil})

      input ->
        send(parent, {:tui_input, input})
        input_reader_loop(parent)
    end
  end

  defp next_loop_event(_input_reader, nil) do
    receive do
      {:tui_input, input} -> {:input, input}
    end
  end

  defp next_loop_event(_input_reader, watch_interval_ms) do
    receive do
      {:tui_input, input} -> {:input, input}
    after
      watch_interval_ms -> :timeout
    end
  end

  defp summarize(nil), do: ""

  defp summarize(value) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 140)
  end

  defp summarize(value), do: inspect(value)

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
