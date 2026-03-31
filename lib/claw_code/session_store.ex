defmodule ClawCode.SessionStore do
  def new_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  def requirements_ledger do
    [
      %{"id" => "control-plane", "statement" => "Elixir remains the control plane."},
      %{"id" => "session-replay", "statement" => "Sessions retain replayable execution state."},
      %{
        "id" => "native-boundary",
        "statement" => "Native helpers stay behind narrow executable boundaries."
      }
    ]
  end

  def save(payload, opts \\ []) do
    write(payload, opts) |> elem(0)
  end

  def write(payload, opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    id = Map.get(payload, :id) || Map.get(payload, "id") || new_id()
    path = Path.join(root, "#{id}.json")
    temp_path = Path.join(root, ".#{id}.json.tmp-#{System.unique_integer([:positive])}")

    try do
      File.mkdir_p!(root)
      document = document(payload, id: id)

      File.write!(temp_path, Jason.encode_to_iodata!(document, pretty: true))
      File.rename!(temp_path, path)

      {path, document}
    after
      File.rm(temp_path)
    end
  end

  def load(session_id, opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    path = Path.join(root, "#{session_id}.json")
    path |> File.read!() |> Jason.decode!()
  end

  def list(opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    limit = Keyword.get(opts, :limit, 20)

    root
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, contents} -> [Jason.decode!(contents)]
        {:error, _reason} -> []
      end
    end)
    |> Enum.sort_by(
      fn session -> {session["updated_at"] || session["saved_at"] || "", session["id"] || ""} end,
      :desc
    )
    |> Enum.take(limit)
  end

  def fetch(session_id, opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    path = Path.join(root, "#{session_id}.json")

    case File.read(path) do
      {:ok, contents} -> {:ok, Jason.decode!(contents)}
      {:error, :enoent} -> :error
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def document(payload, opts \\ []) do
    id = Keyword.get(opts, :id) || Map.get(payload, :id) || Map.get(payload, "id") || new_id()
    payload = stringify_keys(payload)
    saved_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    created_at = Map.get(payload, "created_at") || Map.get(payload, "saved_at") || saved_at

    payload
    |> Map.put_new("id", id)
    |> Map.put_new("created_at", created_at)
    |> Map.put("updated_at", saved_at)
    |> Map.put("saved_at", saved_at)
    |> Map.put_new("messages", [])
    |> Map.put_new("tool_receipts", [])
    |> Map.put_new("turns", 0)
    |> Map.put("requirements", requirements_ledger())
  end

  def root_dir do
    Application.get_env(:claw_code, :session_root, Path.expand(".claw/sessions", File.cwd!()))
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end
end
