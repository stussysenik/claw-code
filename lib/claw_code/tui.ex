defmodule ClawCode.TUI do
  alias ClawCode.{Daemon, Manifest, SessionStore}

  defmodule State do
    @enforce_keys [:opts]
    defstruct opts: [],
              daemon_status: %{},
              doctor: %{},
              sessions: [],
              session_root: nil,
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

  def build_state(opts, daemon_status, notice \\ nil) do
    session_root =
      daemon_status["session_root"] || Keyword.get(opts, :session_root, SessionStore.root_dir())

    sessions = SessionStore.list(limit: Keyword.get(opts, :limit, 8), root: session_root)
    selected_session_id = default_selected_session_id(sessions)
    selected_session = fetch_session(selected_session_id, session_root)

    %State{
      opts: opts,
      daemon_status: daemon_status,
      doctor: Manifest.doctor_payload(opts),
      sessions: sessions,
      session_root: session_root,
      selected_session_id: selected_session_id,
      selected_session: selected_session,
      notice: notice
    }
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

      "help" ->
        {:continue, %{state | notice: help_text()}}

      "cancel" ->
        cancel_selected(state)

      <<"open ", rest::binary>> ->
        open_session(state, rest)

      <<"chat ", prompt::binary>> ->
        send_chat(state, prompt, false)

      <<"resume ", prompt::binary>> ->
        send_chat(state, prompt, true)

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
      "daemon=#{state.daemon_status["status"] || "unknown"} provider=#{state.doctor.provider} model=#{state.doctor.model.value || "missing"} tools=#{state.doctor.tool_policy}",
      "session_root=#{state.session_root}",
      if(state.notice, do: "notice=#{state.notice}"),
      "",
      "## Sessions",
      render_sessions(state.sessions, state.selected_session_id),
      "",
      "## Selected",
      render_selected_session(state.selected_session),
      "",
      "## Commands",
      "chat <prompt> | resume <prompt> | open <n|id> | cancel | tools auto|on|off | refresh | help | quit"
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n")
  end

  defp loop(%State{} = state) do
    IO.write(IO.ANSI.home() <> IO.ANSI.clear())
    IO.puts(render(state))

    case IO.gets("\nclaw> ") do
      nil ->
        :ok

      input ->
        case apply_command(state, input) do
          {:continue, next_state} -> loop(next_state)
          {:halt, _state} -> :ok
        end
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
      |> build_state(refresh_daemon_status(state), notice)
      |> preserve_selection(state.selected_session_id)

    {:continue, next_state}
  end

  defp preserve_selection(%State{} = state, nil), do: state

  defp preserve_selection(%State{} = state, selected_session_id) do
    selected_session = fetch_session(selected_session_id, state.session_root)

    %{
      state
      | selected_session_id: selected_session_id || state.selected_session_id,
        selected_session: selected_session || state.selected_session
    }
  end

  defp refresh_daemon_status(%State{opts: opts}) do
    {:ok, status} = Daemon.status(opts)
    status
  end

  defp open_session(%State{} = state, value) do
    case resolve_session_id(String.trim(value), state.sessions) do
      nil ->
        {:continue, %{state | notice: "Session not found: #{String.trim(value)}"}}

      session_id ->
        selected_session = fetch_session(session_id, state.session_root)

        {:continue,
         %{
           state
           | selected_session_id: session_id,
             selected_session: selected_session,
             notice: "Opened session #{session_id}."
         }}
    end
  end

  defp send_chat(%State{} = state, prompt, resume?) do
    prompt = String.trim(prompt)

    if prompt == "" do
      {:continue, %{state | notice: "Prompt is required."}}
    else
      chat_opts =
        if resume? and state.selected_session_id do
          Keyword.put(state.opts, :session_id, state.selected_session_id)
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

  defp rebuild_with_opts(%State{} = state, opts, notice) do
    next_state =
      opts
      |> build_state(refresh_daemon_status(%{state | opts: opts}), notice)
      |> preserve_selection(state.selected_session_id)

    {:continue, next_state}
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

  defp resolve_session_id(value, sessions) do
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

  defp render_selected_session(nil), do: "none"

  defp render_selected_session(session) do
    [
      "id=#{session["id"]}",
      "stop=#{session["stop_reason"] || "unknown"} run=#{get_in(session, ["run_state", "status"]) || "unknown"} turns=#{session["turns"] || 0}",
      "messages:",
      render_messages(session["messages"] || []),
      "receipts:",
      render_receipts(session["tool_receipts"] || [])
    ]
    |> Enum.join("\n")
  end

  defp render_messages([]), do: "  none"

  defp render_messages(messages) do
    messages
    |> Enum.take(-6)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {message, index} ->
      role = message["role"] || "unknown"
      content = summarize(message["content"])
      "  #{index}. #{role}: #{content}"
    end)
  end

  defp render_receipts([]), do: "  none"

  defp render_receipts(receipts) do
    receipts
    |> Enum.take(-4)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {receipt, index} ->
      tool = receipt["tool_name"] || receipt[:tool_name] || receipt["tool"] || "unknown"
      status = receipt["status"] || receipt[:status] || "unknown"
      "  #{index}. #{tool} #{status}"
    end)
  end

  defp help_text do
    "Commands: chat <prompt>, resume <prompt>, open <n|id>, cancel, tools auto|on|off, refresh, help, quit"
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
