defmodule ClawCode.SessionServerTest do
  use ExUnit.Case, async: false

  alias ClawCode.{SessionServer, SessionStore}

  test "session server persists and snapshots a session" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-server-test-#{SessionStore.new_id()}")
    File.rm_rf(root)

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

  test "session server preserves created_at across multiple writes" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-server-created-at-test")
    {:ok, session_id, pid} = SessionServer.ensure_started("session-created", root: root)

    on_exit(fn ->
      SessionServer.close(pid)
    end)

    {_path, first} = SessionServer.persist(pid, %{"prompt" => "first", "output" => "one"})
    Process.sleep(1_000)
    {_path, second} = SessionServer.persist(pid, %{"prompt" => "second", "output" => "two"})

    assert first["created_at"] == second["created_at"]
    assert first["saved_at"] != second["saved_at"]

    persisted = SessionStore.load(session_id, root: root)
    assert persisted["created_at"] == first["created_at"]
  end

  test "session server enforces a single active run and can cancel it" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-server-run-test-#{SessionStore.new_id()}")

    File.rm_rf(root)

    {:ok, session_id, pid} = SessionServer.ensure_started("session-runner", root: root)

    on_exit(fn ->
      SessionServer.close(pid)
    end)

    {:ok, document} = SessionServer.begin_run(pid)
    assert document["run_state"]["status"] == "running"

    task_pid =
      spawn(fn ->
        Process.sleep(5_000)
      end)

    monitor_ref = Process.monitor(task_pid)
    assert :ok = SessionServer.attach_run(pid, task_pid)
    assert {:error, :session_busy, _document} = SessionServer.begin_run(pid)

    assert {:ok, {_path, cancelled}} = SessionServer.cancel_run(pid)
    assert cancelled["stop_reason"] == "cancelled"
    assert cancelled["run_state"]["last_stop_reason"] == "cancelled"
    assert_receive {:DOWN, ^monitor_ref, :process, ^task_pid, :killed}, 1_000

    persisted = SessionStore.load(session_id, root: root)
    assert persisted["stop_reason"] == "cancelled"
  end

  test "late finish_run does not overwrite a cancelled terminal state" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-server-terminal-#{SessionStore.new_id()}")

    File.rm_rf(root)

    {:ok, session_id, pid} = SessionServer.ensure_started("session-terminal", root: root)

    on_exit(fn ->
      SessionServer.close(pid)
    end)

    assert {:ok, _document} = SessionServer.begin_run(pid)
    task_pid = spawn(fn -> Process.sleep(5_000) end)
    assert :ok = SessionServer.attach_run(pid, task_pid)
    assert {:ok, {_path, cancelled}} = SessionServer.cancel_run(pid)
    assert cancelled["stop_reason"] == "cancelled"

    {_path, finished} =
      SessionServer.finish_run(pid, %{
        "prompt" => "should not win",
        "output" => "late reply",
        "stop_reason" => "completed"
      })

    assert finished["stop_reason"] == "cancelled"
    assert finished["output"] == "Run cancelled."

    persisted = SessionStore.load(session_id, root: root)
    assert persisted["stop_reason"] == "cancelled"
    assert persisted["output"] == "Run cancelled."
  end
end
