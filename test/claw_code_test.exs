defmodule ClawCodeTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias ClawCode.{CLI, SessionStore}

  test "registry loads mirrored command and tool inventories" do
    stats = ClawCode.Registry.stats()

    assert stats.commands >= 150
    assert stats.tools >= 100
  end

  test "router balances command and tool matches" do
    matches = ClawCode.Router.route("review MCP tool", limit: 5, native: false)

    assert Enum.any?(matches, &(&1.kind == :command))
    assert Enum.any?(matches, &(&1.kind == :tool))
  end

  test "builtin runtime tools execute through host adapters" do
    assert {:ok, python} =
             ClawCode.Tools.Builtin.execute("python_eval", %{"code" => "print('python-ok')"})

    assert python =~ "python-ok"

    assert {:ok, lua} =
             ClawCode.Tools.Builtin.execute("lua_eval", %{"code" => "print('lua-ok')"})

    assert lua =~ "lua-ok"

    assert {:ok, lisp} =
             ClawCode.Tools.Builtin.execute("lisp_eval", %{"code" => "(write-line \"lisp-ok\")"})

    assert lisp =~ "lisp-ok"
  end

  test "native ranker builds and returns ranked matches" do
    entries = ClawCode.Registry.entries(:all)
    ranked = ClawCode.NativeRanker.rank("MCPTool", entries)

    assert Enum.any?(ranked, &(&1.name == "MCPTool" and &1.score > 0))
  end

  test "symphony runs parallel agents" do
    report = ClawCode.Symphony.run("review MCP tool", native: false)
    rendered = ClawCode.Symphony.render(report)

    assert rendered =~ "# Symphony"
    assert rendered =~ "review MCP tool"
    assert rendered =~ "## Runtimes"
  end

  test "chat persists missing-provider sessions without crashing" do
    result =
      ClawCode.Runtime.chat("review MCP tool",
        provider: "generic",
        api_key: nil,
        base_url: nil,
        model: nil
      )

    assert result.stop_reason == "missing_provider_config"
    assert File.exists?(result.session_path)
  end

  test "load-session exposes the persisted requirements count" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-session-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)

    path = SessionStore.save(%{prompt: "hello", output: "world", messages: []}, root: root)
    session_id = Path.basename(path, ".json")

    output =
      capture_io(fn ->
        assert 0 == CLI.run(["load-session", session_id])
      end)

    assert output =~ "created="
    assert output =~ "updated="
    assert output =~ "requirements=#{length(SessionStore.requirements_ledger())}"
    assert output =~ "tool_receipts=0"
  end
end
