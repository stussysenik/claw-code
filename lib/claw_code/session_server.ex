defmodule ClawCode.SessionServer do
  use GenServer

  alias ClawCode.SessionStore

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def ensure_started(session_id \\ nil, opts \\ []) do
    session_id = session_id || SessionStore.new_id()

    case Registry.lookup(ClawCode.SessionRegistry, session_id) do
      [{pid, _value}] ->
        {:ok, session_id, pid}

      [] ->
        child_spec = {__MODULE__, Keyword.merge(opts, session_id: session_id)}

        case DynamicSupervisor.start_child(ClawCode.SessionSupervisor, child_spec) do
          {:ok, pid} -> {:ok, session_id, pid}
          {:error, {:already_started, pid}} -> {:ok, session_id, pid}
          other -> other
        end
    end
  end

  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)
  def persist(pid, payload) when is_pid(pid), do: GenServer.call(pid, {:persist, payload})
  def close(pid) when is_pid(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(opts) do
    root = Keyword.get(opts, :root, SessionStore.root_dir())
    session_id = Keyword.fetch!(opts, :session_id)

    document =
      case SessionStore.fetch(session_id, root: root) do
        {:ok, session} -> session
        :error -> SessionStore.document(%{id: session_id})
      end

    {:ok, %{id: session_id, root: root, document: document}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.document, state}
  end

  def handle_call({:persist, payload}, _from, state) do
    payload = SessionStore.document(payload, id: state.id)

    merged =
      state.document
      |> Map.merge(payload)

    {path, document} = SessionStore.write(merged, root: state.root)

    {:reply, {path, document}, %{state | document: document}}
  end

  defp via(session_id) do
    {:via, Registry, {ClawCode.SessionRegistry, session_id}}
  end
end
