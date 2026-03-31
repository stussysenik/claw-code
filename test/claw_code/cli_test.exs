defmodule ClawCode.CLITest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias ClawCode.{CLI, SessionStore}

  test "summary command renders app summary" do
    output = capture_io(fn -> assert CLI.run(["summary"]) == 0 end)
    assert output =~ "# Claw Code Elixir"
  end

  test "commands and tools commands render indexes" do
    command_output =
      capture_io(fn -> assert CLI.run(["commands", "--limit", "3", "--query", "review"]) == 0 end)

    tool_output =
      capture_io(fn -> assert CLI.run(["tools", "--limit", "3", "--query", "MCP"]) == 0 end)

    assert command_output =~ "Command entries"
    assert tool_output =~ "Tool entries"
  end

  test "route and bootstrap commands run" do
    route_output =
      capture_io(fn ->
        assert CLI.run(["route", "--limit", "5", "--no-native", "review MCP tool"]) == 0
      end)

    bootstrap_output =
      capture_io(fn ->
        assert CLI.run(["bootstrap", "--limit", "5", "--no-native", "review MCP tool"]) == 0
      end)

    assert route_output =~ "review"
    assert bootstrap_output =~ "# Bootstrap"
  end

  test "show and exec commands run" do
    show_output = capture_io(fn -> assert CLI.run(["show-command", "review"]) == 0 end)

    exec_output =
      capture_io(fn -> assert CLI.run(["exec-tool", "MCPTool", "fetch resource list"]) == 0 end)

    assert show_output =~ "review"
    assert exec_output =~ "Mirrored tool 'MCPTool'"
  end

  test "resume-session reuses an existing session id" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-resume-session-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)

    path =
      SessionStore.save(
        %{
          prompt: "hello",
          output: "world",
          stop_reason: "completed",
          messages: [%{"role" => "system", "content" => "seed"}]
        },
        root: root
      )

    session_id = Path.basename(path, ".json")

    output =
      capture_io(fn ->
        assert CLI.run(["resume-session", session_id, "--provider", "generic", "resume me"]) == 0
      end)

    assert output =~ "Session id: #{session_id}"
  end
end
