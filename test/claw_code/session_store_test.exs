defmodule ClawCode.SessionStoreTest do
  use ExUnit.Case, async: true

  alias ClawCode.SessionStore

  test "round-trips saved sessions" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-store-test")
    path = SessionStore.save(%{prompt: "hello", output: "world", messages: []}, root: root)
    session = SessionStore.load(Path.basename(path, ".json"), root: root)

    assert session["prompt"] == "hello"
    assert session["output"] == "world"
    assert session["requirements"] == SessionStore.requirements_ledger()
    assert session["tool_receipts"] == []
  end

  test "overwrites ad hoc requirements with the canonical ledger" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-store-ledger-test")

    path =
      SessionStore.save(
        %{
          prompt: "hello",
          output: "world",
          messages: [],
          requirements: [%{"id" => "temporary", "statement" => "do not keep this"}]
        },
        root: root
      )

    session = SessionStore.load(Path.basename(path, ".json"), root: root)

    assert session["requirements"] == SessionStore.requirements_ledger()
  end

  test "fetch returns :error for a missing session" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-store-missing-test")
    assert SessionStore.fetch("missing-session", root: root) == :error
  end

  test "fetch returns a typed invalid-session error for malformed or partial json" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-session-store-invalid-test-#{SessionStore.new_id()}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    File.write!(Path.join(root, "broken-session.json"), ~s({"prompt":"hello"))

    assert {:error, {:invalid_session, details} = reason} =
             SessionStore.fetch("broken-session", root: root)

    assert details.session_id == "broken-session"
    assert details.path == Path.join(root, "broken-session.json")
    assert SessionStore.error_message(reason) =~ "Session state is invalid for broken-session"
  end

  test "fetch returns a typed invalid-session error for non-object json" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-session-store-invalid-type-test-#{SessionStore.new_id()}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    File.write!(Path.join(root, "array-session.json"), ~s(["not", "a", "session"]))

    assert {:error, {:invalid_session, details} = reason} =
             SessionStore.fetch("array-session", root: root)

    assert details.session_id == "array-session"
    assert SessionStore.error_message(reason) =~ "expected JSON object at root, got array"
  end

  test "document preserves created_at and emits updated_at" do
    document =
      SessionStore.document(%{"id" => "session-1", "created_at" => "2026-03-31T00:00:00Z"})

    assert document["created_at"] == "2026-03-31T00:00:00Z"
    assert document["updated_at"]
    assert document["turns"] == 0
  end

  test "list returns saved sessions" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-store-list-test")

    SessionStore.save(%{id: "session-1", prompt: "hello", output: "world", messages: []},
      root: root
    )

    sessions = SessionStore.list(root: root, limit: 10)

    assert Enum.any?(sessions, &(&1["id"] == "session-1"))
  end

  test "list can filter sessions by query text" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-store-query-test")

    SessionStore.save(
      %{id: "session-alpha", prompt: "review alpha repo", output: "done", messages: []},
      root: root
    )

    SessionStore.save(
      %{id: "session-beta", prompt: "inspect beta service", output: "done", messages: []},
      root: root
    )

    sessions = SessionStore.list(root: root, limit: 10, query: "beta")

    assert Enum.map(sessions, & &1["id"]) == ["session-beta"]
  end

  test "list can filter sessions by image filename in multimodal message content" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-session-store-multimodal-query-#{SessionStore.new_id()}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    SessionStore.save(
      %{
        id: "session-image",
        prompt: "inspect screenshot",
        messages: [
          %{
            "role" => "user",
            "content" => [
              %{"type" => "text", "text" => "inspect screenshot"},
              %{
                "type" => "input_image",
                "path" => "/tmp/example-diagram.png",
                "mime_type" => "image/png"
              }
            ]
          }
        ]
      },
      root: root
    )

    sessions = SessionStore.list(root: root, limit: 10, query: "diagram.png")

    assert Enum.map(sessions, & &1["id"]) == ["session-image"]
  end

  test "list supports offset after sorting and query filtering" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-store-offset-test-#{SessionStore.new_id()}")

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    write_session(root, %{
      "id" => "session-alpha-1",
      "updated_at" => "2026-04-01T00:00:01Z",
      "saved_at" => "2026-04-01T00:00:01Z",
      "prompt" => "alpha first",
      "messages" => []
    })

    write_session(root, %{
      "id" => "session-alpha-2",
      "updated_at" => "2026-04-01T00:00:02Z",
      "saved_at" => "2026-04-01T00:00:02Z",
      "prompt" => "alpha second",
      "messages" => []
    })

    write_session(root, %{
      "id" => "session-beta",
      "updated_at" => "2026-04-01T00:00:03Z",
      "saved_at" => "2026-04-01T00:00:03Z",
      "prompt" => "beta third",
      "messages" => []
    })

    sessions = SessionStore.list(root: root, limit: 1, offset: 1, query: "alpha")

    assert Enum.map(sessions, & &1["id"]) == ["session-alpha-1"]
  end

  test "list ignores malformed or non-object json files" do
    root = Path.join(System.tmp_dir!(), "claw-code-session-store-robust-list-test")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    SessionStore.save(%{id: "session-1", prompt: "hello", output: "world", messages: []},
      root: root
    )

    File.write!(Path.join(root, "broken.json"), "{not-json")
    File.write!(Path.join(root, "array.json"), ~s(["not", "a", "session"]))

    sessions = SessionStore.list(root: root, limit: 10)

    assert Enum.map(sessions, & &1["id"]) == ["session-1"]
  end

  test "health summarizes running failed recovered and invalid sessions" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-session-store-health-test-#{SessionStore.new_id()}")

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    write_session(root, %{
      "id" => "session-completed",
      "created_at" => "2026-04-01T00:00:00Z",
      "updated_at" => "2026-04-01T00:00:01Z",
      "saved_at" => "2026-04-01T00:00:01Z",
      "provider" => %{"provider" => "glm", "model" => "glm-4.7"},
      "stop_reason" => "completed",
      "run_state" => %{
        "status" => "idle",
        "finished_at" => "2026-04-01T00:00:01Z",
        "last_stop_reason" => "completed"
      },
      "messages" => [],
      "tool_receipts" => []
    })

    write_session(root, %{
      "id" => "session-recovered",
      "created_at" => "2026-04-01T00:00:00Z",
      "updated_at" => "2026-04-01T00:00:02Z",
      "saved_at" => "2026-04-01T00:00:02Z",
      "provider" => %{"provider" => "glm", "model" => "glm-4.7"},
      "output" => "Session run interrupted during recovery.",
      "stop_reason" => "run_interrupted",
      "run_state" => %{
        "status" => "idle",
        "finished_at" => "2026-04-01T00:00:02Z",
        "last_stop_reason" => "run_interrupted"
      },
      "messages" => [],
      "tool_receipts" => []
    })

    write_session(root, %{
      "id" => "session-failed",
      "created_at" => "2026-04-01T00:00:00Z",
      "updated_at" => "2026-04-01T00:00:03Z",
      "saved_at" => "2026-04-01T00:00:03Z",
      "provider" => %{"provider" => "generic", "model" => "local-model"},
      "output" => "provider request failed with status 401: unauthorized",
      "stop_reason" => "provider_error",
      "run_state" => %{
        "status" => "idle",
        "finished_at" => "2026-04-01T00:00:03Z",
        "last_stop_reason" => "provider_error"
      },
      "messages" => [],
      "tool_receipts" => [
        %{
          "tool_name" => "shell",
          "status" => "error",
          "duration_ms" => 17,
          "started_at" => "2026-04-01T00:00:03Z"
        }
      ]
    })

    write_session(root, %{
      "id" => "session-running",
      "created_at" => "2026-04-01T00:00:00Z",
      "updated_at" => "2026-04-01T00:00:04Z",
      "saved_at" => "2026-04-01T00:00:04Z",
      "provider" => %{"provider" => "nim", "model" => "nvidia/model"},
      "stop_reason" => "running",
      "run_state" => %{
        "status" => "running",
        "started_at" => "2026-04-01T00:00:04Z"
      },
      "messages" => [],
      "tool_receipts" => [
        %{
          "tool_name" => "shell",
          "status" => "ok",
          "duration_ms" => 42,
          "started_at" => "2026-04-01T00:00:04Z"
        }
      ]
    })

    File.write!(Path.join(root, "broken.json"), "{not-json")

    health = SessionStore.health(root: root)

    assert health["signals"] == ["busy", "failed", "partially_recovered", "invalid_sessions"]
    assert health["counts"]["total"] == 4
    assert health["counts"]["invalid"] == 1
    assert health["counts"]["running"] == 1
    assert health["counts"]["completed"] == 1
    assert health["counts"]["failed"] == 1
    assert health["counts"]["recovered"] == 1

    assert health["latest_running"]["id"] == "session-running"
    assert health["latest_running"]["last_receipt"]["tool"] == "shell"
    assert health["latest_running"]["last_receipt"]["status"] == "ok"

    assert health["latest_failed"]["id"] == "session-failed"
    assert health["latest_failed"]["stop_reason"] == "provider_error"
    assert health["latest_failed"]["detail"] =~ "401"
    assert health["latest_failed"]["last_receipt"]["status"] == "error"

    assert health["latest_recovered"]["id"] == "session-recovered"
    assert health["latest_recovered"]["stop_reason"] == "run_interrupted"
  end

  test "recover_running_sessions rewrites stale running sessions and leaves others untouched" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-session-store-recover-running-#{SessionStore.new_id()}"
      )

    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    write_session(root, %{
      "id" => "session-running",
      "created_at" => "2026-04-01T00:00:00Z",
      "updated_at" => "2026-04-01T00:00:01Z",
      "saved_at" => "2026-04-01T00:00:01Z",
      "output" => "partial output",
      "stop_reason" => "running",
      "run_state" => %{
        "status" => "running",
        "started_at" => "2026-04-01T00:00:01Z"
      },
      "messages" => [],
      "tool_receipts" => []
    })

    write_session(root, %{
      "id" => "session-completed",
      "created_at" => "2026-04-01T00:00:00Z",
      "updated_at" => "2026-04-01T00:00:02Z",
      "saved_at" => "2026-04-01T00:00:02Z",
      "output" => "done",
      "stop_reason" => "completed",
      "run_state" => %{
        "status" => "idle",
        "finished_at" => "2026-04-01T00:00:02Z",
        "last_stop_reason" => "completed"
      },
      "messages" => [],
      "tool_receipts" => []
    })

    recovered = SessionStore.recover_running_sessions(root: root)

    assert Enum.map(recovered, & &1["id"]) == ["session-running"]

    running = SessionStore.load("session-running", root: root)
    assert running["stop_reason"] == "run_interrupted"
    assert running["output"] == "partial output"
    assert running["run_state"]["status"] == "idle"
    assert running["run_state"]["last_stop_reason"] == "run_interrupted"

    completed = SessionStore.load("session-completed", root: root)
    assert completed["stop_reason"] == "completed"
    assert completed["output"] == "done"
    assert completed["run_state"]["last_stop_reason"] == "completed"
  end

  defp write_session(root, payload) do
    path = Path.join(root, "#{payload["id"]}.json")
    File.write!(path, Jason.encode_to_iodata!(payload, pretty: true))
    path
  end
end
