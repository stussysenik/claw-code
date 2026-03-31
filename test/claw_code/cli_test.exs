defmodule ClawCode.CLITest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias ClawCode.CLI

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
end
