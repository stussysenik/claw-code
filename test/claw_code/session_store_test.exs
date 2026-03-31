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

  test "document preserves created_at and emits updated_at" do
    document =
      SessionStore.document(%{"id" => "session-1", "created_at" => "2026-03-31T00:00:00Z"})

    assert document["created_at"] == "2026-03-31T00:00:00Z"
    assert document["updated_at"]
    assert document["turns"] == 0
  end
end
