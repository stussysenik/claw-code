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

  test "record_run_exit persists crash state synchronously before later inspection" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-server-crash-#{SessionStore.new_id()}")

    File.rm_rf(root)

    {:ok, session_id, pid} = SessionServer.ensure_started("session-crash", root: root)

    on_exit(fn ->
      SessionServer.close(pid)
    end)

    assert {:ok, _document} = SessionServer.begin_run(pid)
    task_pid = spawn(fn -> Process.sleep(5_000) end)
    assert :ok = SessionServer.attach_run(pid, task_pid)

    {_path, crashed} = SessionServer.record_run_exit(pid, :boom)

    assert crashed["stop_reason"] == "run_crashed"
    assert crashed["output"] == "Session run crashed: :boom"
    assert crashed["run_state"]["status"] == "idle"
    assert crashed["run_state"]["last_stop_reason"] == "run_crashed"

    snapshot = SessionServer.snapshot(pid)
    assert snapshot["stop_reason"] == "run_crashed"
    assert snapshot["output"] == "Session run crashed: :boom"

    persisted = SessionStore.load(session_id, root: root)
    assert persisted["stop_reason"] == "run_crashed"
    assert persisted["output"] == "Session run crashed: :boom"

    {_path, finished} =
      SessionServer.finish_run(pid, %{
        "prompt" => "should not win",
        "output" => "late reply",
        "stop_reason" => "completed"
      })

    assert finished["stop_reason"] == "run_crashed"
    assert finished["output"] == "Session run crashed: :boom"
  end

  test "session server reconciles a persisted running session during recovery" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-server-recovery-#{SessionStore.new_id()}")

    File.rm_rf(root)

    SessionStore.save(
      %{
        id: "session-recovered",
        prompt: "recover me",
        stop_reason: "running",
        run_state: %{"status" => "running", "started_at" => "2026-04-01T00:00:00Z"},
        messages: [%{"role" => "user", "content" => "recover me"}]
      },
      root: root
    )

    {:ok, "session-recovered", pid} =
      SessionServer.ensure_started("session-recovered", root: root)

    on_exit(fn ->
      SessionServer.close(pid)
    end)

    snapshot = SessionServer.snapshot(pid)
    assert snapshot["stop_reason"] == "run_interrupted"
    assert snapshot["run_state"]["status"] == "idle"
    assert snapshot["run_state"]["last_stop_reason"] == "run_interrupted"
    assert snapshot["output"] == "Session run interrupted during recovery."

    persisted = SessionStore.load("session-recovered", root: root)
    assert persisted["stop_reason"] == "run_interrupted"
    assert persisted["run_state"]["status"] == "idle"

    assert {:ok, rerun} = SessionServer.begin_run(pid)
    assert rerun["run_state"]["status"] == "running"
  end

  test "session server refuses to start against an invalid persisted session" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-server-invalid-#{SessionStore.new_id()}")

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    File.write!(Path.join(root, "broken-session.json"), "{not-json")

    assert {:error, {:invalid_session, details} = reason} =
             SessionServer.ensure_started("broken-session", root: root)

    assert details.session_id == "broken-session"
    assert SessionStore.error_message(reason) =~ "Session state is invalid for broken-session"
  end
end
