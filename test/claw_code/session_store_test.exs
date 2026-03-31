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
end
