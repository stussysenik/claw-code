defmodule ClawCode.SessionServer do
  use GenServer

  alias ClawCode.SessionStore

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def ensure_started(session_id \\ nil, opts \\ []) do
    session_id = session_id || SessionStore.new_id()
    root = Keyword.get(opts, :root, SessionStore.root_dir())

    case Registry.lookup(ClawCode.SessionRegistry, session_id) do
      [{pid, _value}] ->
        {:ok, session_id, pid}

      [] ->
        case SessionStore.fetch(session_id, root: root) do
          {:error, {:invalid_session, _details} = reason} ->
            {:error, reason}

          _other ->
            child_spec = {__MODULE__, Keyword.merge(opts, session_id: session_id)}

            case DynamicSupervisor.start_child(ClawCode.SessionSupervisor, child_spec) do
              {:ok, pid} -> {:ok, session_id, pid}
              {:error, {:already_started, pid}} -> {:ok, session_id, pid}
              other -> other
            end
        end
    end
  end

  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)
  def begin_run(pid) when is_pid(pid), do: GenServer.call(pid, :begin_run)
  def attach_run(pid, task_pid) when is_pid(pid), do: GenServer.call(pid, {:attach_run, task_pid})

  def record_run_exit(pid, reason) when is_pid(pid),
    do: GenServer.call(pid, {:record_run_exit, reason})

  def checkpoint(pid, payload) when is_pid(pid), do: GenServer.call(pid, {:checkpoint, payload})
  def finish_run(pid, payload) when is_pid(pid), do: GenServer.call(pid, {:finish_run, payload})
  def cancel_run(pid) when is_pid(pid), do: GenServer.call(pid, :cancel_run)
  def persist(pid, payload) when is_pid(pid), do: GenServer.call(pid, {:persist, payload})
  def close(pid) when is_pid(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(opts) do
    root = Keyword.get(opts, :root, SessionStore.root_dir())
    session_id = Keyword.fetch!(opts, :session_id)

    document =
      case SessionStore.fetch(session_id, root: root) do
        {:ok, session} -> reconcile_loaded_session(session, root)
        :error -> SessionStore.document(%{id: session_id})
        {:error, {:invalid_session, _details} = reason} -> {:stop, reason}
      end

    case document do
      {:stop, reason} ->
        {:stop, reason}

      document ->
        {:ok, %{id: session_id, root: root, document: document, active_run: nil}}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.document, state}
  end

  def handle_call(:begin_run, _from, %{active_run: nil} = state) do
    run_state = %{"status" => "running", "started_at" => utc_now()}

    {_path, document, state} =
      persist_document(state, %{"run_state" => run_state, "stop_reason" => "running"})

    {:reply, {:ok, document}, %{state | active_run: %{run_state: run_state}}}
  end

  def handle_call(:begin_run, _from, state) do
    {:reply, {:error, :session_busy, state.document}, state}
  end

  def handle_call({:attach_run, _task_pid}, _from, %{active_run: nil} = state) do
    {:reply, {:error, :not_running}, state}
  end

  def handle_call({:attach_run, task_pid}, _from, state) do
    ref = Process.monitor(task_pid)
    active_run = Map.merge(state.active_run, %{task_pid: task_pid, monitor_ref: ref})
    {:reply, :ok, %{state | active_run: active_run}}
  end

  def handle_call({:record_run_exit, reason}, _from, state) do
    {path, document, state} = finalize_run_exit(state, reason)
    {:reply, {path, document}, state}
  end

  def handle_call({:checkpoint, payload}, _from, state) do
    if is_nil(state.active_run) do
      {:reply, {SessionStore.path(state.id, root: state.root), state.document}, state}
    else
      payload =
        Map.put(payload, "run_state", checkpoint_run_state(state))
        |> Map.put_new("stop_reason", "running")

      {path, document, state} = persist_document(state, payload)
      {:reply, {path, document}, state}
    end
  end

  def handle_call({:finish_run, _payload}, _from, %{active_run: nil} = state) do
    # A late completion from a cancelled or crashed task must not overwrite
    # the terminal state already persisted by the session server.
    {:reply, {SessionStore.path(state.id, root: state.root), state.document}, state}
  end

  def handle_call({:finish_run, payload}, _from, state) do
    payload =
      payload
      |> Map.put(
        "run_state",
        finished_run_state(payload["stop_reason"] || payload[:stop_reason] || "completed")
      )

    {path, document, state} =
      state
      |> clear_active_run()
      |> persist_document(payload)

    {:reply, {path, document}, state}
  end

  def handle_call(:cancel_run, _from, %{active_run: nil} = state) do
    {:reply, {:error, :not_running}, state}
  end

  def handle_call(:cancel_run, _from, state) do
    state =
      case state.active_run do
        %{task_pid: task_pid} when is_pid(task_pid) ->
          Process.exit(task_pid, :kill)
          clear_active_run(state)

        _other ->
          clear_active_run(state)
      end

    {path, document, state} =
      persist_document(state, %{
        "stop_reason" => "cancelled",
        "output" => "Run cancelled.",
        "run_state" => finished_run_state("cancelled")
      })

    {:reply, {:ok, {path, document}}, state}
  end

  def handle_call({:persist, payload}, _from, state) do
    {path, document, state} = persist_document(state, payload)
    {:reply, {path, document}, state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{active_run: %{monitor_ref: ref}} = state
      ) do
    {_path, _document, state} = finalize_run_exit(state, reason)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp via(session_id) do
    {:via, Registry, {ClawCode.SessionRegistry, session_id}}
  end

  defp persist_document(state, payload) do
    document =
      state.document
      |> Map.merge(stringify_keys(payload))
      |> Map.put_new("created_at", state.document["created_at"])
      |> SessionStore.document(id: state.id)

    {path, document} = SessionStore.write(document, root: state.root)
    {path, document, %{state | document: document}}
  end

  defp reconcile_loaded_session(session, root) do
    case SessionStore.recover_running_session(session, root: root) do
      {:ok, persisted} -> persisted
      :noop -> session
    end
  end

  defp finalize_run_exit(state, reason) do
    state = clear_active_run(state)

    if crash_reason?(reason) and state.document["stop_reason"] == "running" do
      persist_document(state, %{
        "stop_reason" => "run_crashed",
        "output" => "Session run crashed: #{inspect(reason)}",
        "run_state" => finished_run_state("run_crashed")
      })
    else
      {SessionStore.path(state.id, root: state.root), state.document, state}
    end
  end

  defp clear_active_run(%{active_run: nil} = state), do: state

  defp clear_active_run(state) do
    if ref = get_in(state, [:active_run, :monitor_ref]) do
      Process.demonitor(ref, [:flush])
    end

    %{state | active_run: nil}
  end

  defp checkpoint_run_state(state) do
    case state.document["run_state"] do
      %{"started_at" => started_at} -> %{"status" => "running", "started_at" => started_at}
      _other -> %{"status" => "running", "started_at" => utc_now()}
    end
  end

  defp finished_run_state(stop_reason) do
    %{
      "status" => "idle",
      "finished_at" => utc_now(),
      "last_stop_reason" => stop_reason
    }
  end

  defp crash_reason?(:normal), do: false
  defp crash_reason?(:shutdown), do: false
  defp crash_reason?({:shutdown, _reason}), do: false
  defp crash_reason?(_reason), do: true

  defp utc_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
