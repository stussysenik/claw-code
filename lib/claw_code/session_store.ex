defmodule ClawCode.SessionStore do
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
    root = Keyword.get(opts, :root, root_dir())
    id = Map.get(payload, :id, random_id())
    path = Path.join(root, "#{id}.json")

    File.mkdir_p!(root)

    document =
      payload
      |> Map.put_new(:id, id)
      |> Map.put_new(
        :saved_at,
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )
      |> Map.put_new(:tool_receipts, [])
      |> Map.put(:requirements, requirements_ledger())

    File.write!(path, Jason.encode_to_iodata!(document, pretty: true))
    path
  end

  def load(session_id, opts \\ []) do
    root = Keyword.get(opts, :root, root_dir())
    path = Path.join(root, "#{session_id}.json")
    path |> File.read!() |> Jason.decode!()
  end

  def root_dir do
    Application.get_env(:claw_code, :session_root, Path.expand(".claw/sessions", File.cwd!()))
  end

  defp random_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
