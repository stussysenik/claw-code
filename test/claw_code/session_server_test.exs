defmodule ClawCode.SessionServerTest do
  use ExUnit.Case, async: false

  alias ClawCode.{SessionServer, SessionStore}

  test "session server persists and snapshots a session" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-server-test")
    {:ok, session_id, pid} = SessionServer.ensure_started("session-server", root: root)

    on_exit(fn ->
      SessionServer.close(pid)
    end)

    snapshot = SessionServer.snapshot(pid)
    assert snapshot["id"] == session_id

    {path, document} =
      SessionServer.persist(pid, %{
        "prompt" => "hello",
        "output" => "world",
        "messages" => [%{"role" => "user", "content" => "hello"}],
        "turns" => 1
      })

    assert Path.basename(path, ".json") == session_id
    assert document["output"] == "world"

    persisted = SessionStore.load(session_id, root: root)
    assert persisted["messages"] == [%{"role" => "user", "content" => "hello"}]
    assert persisted["turns"] == 1
  end
end
