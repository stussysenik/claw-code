defmodule ClawCode.ToolsTest do
  use ExUnit.Case, async: true

  alias ClawCode.Tools.Builtin

  test "shell tool returns a receipt when enabled" do
    assert {:ok, output, receipt} =
             Builtin.execute_with_receipt(
               "shell",
               %{"command" => "printf shell-ok"},
               allow_shell: true
             )

    assert output == "shell-ok"
    assert receipt.tool == "shell"
    assert receipt.kind == "shell"
    assert receipt.invocation == "printf shell-ok"
    assert receipt.cwd == File.cwd!()
    assert receipt.exit_status == 0
    assert receipt.status == "ok"
    assert receipt.duration_ms >= 0
    assert receipt.output == "shell-ok"
  end

  test "shell tool reports timeouts with a receipt" do
    assert {:error, message, receipt} =
             Builtin.execute_with_receipt(
               "shell",
               %{"command" => "sleep 1", "timeout_ms" => 10},
               allow_shell: true
             )

    assert message =~ "timed out"
    assert receipt.tool == "shell"
    assert receipt.status == "timeout"
    assert receipt.exit_status == "timeout"
    assert receipt.duration_ms >= 0
  end

  test "shell tool blocks destructive prefixes" do
    assert {:error, message, receipt} =
             Builtin.execute_with_receipt(
               "shell",
               %{"command" => "rm -rf /tmp/example"},
               allow_shell: true
             )

    assert message =~ "blocked by policy"
    assert receipt.status == "blocked"
    assert receipt.exit_status == "blocked"
  end
end
