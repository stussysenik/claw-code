defmodule ClawCode.QAScriptTest do
  use ExUnit.Case, async: false

  test "qa.sh dispatches the native Ralph loop" do
    {output, status} =
      System.cmd("bash", ["scripts/qa.sh", "native"],
        cd: File.cwd!(),
        env: [{"RALPH_MAX_CYCLES", "0"}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "running native Ralph loop"
    assert output =~ "native Ralph loop complete"
  end

  test "qa.sh dispatches the recovery Ralph loop" do
    {output, status} =
      System.cmd("bash", ["scripts/qa.sh", "recovery"],
        cd: File.cwd!(),
        env: [{"RALPH_MAX_CYCLES", "0"}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "running recovery Ralph loop"
    assert output =~ "recovery Ralph loop complete"
  end

  test "qa.sh dispatches the provider-live Ralph loop" do
    {output, status} =
      System.cmd("bash", ["scripts/qa.sh", "provider-live"],
        cd: File.cwd!(),
        env: [{"RALPH_MAX_CYCLES", "0"}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "running provider-live Ralph loop"
    assert output =~ "provider-live Ralph loop complete"
  end

  test "qa.sh dispatches the release Ralph loop" do
    {output, status} =
      System.cmd("bash", ["scripts/qa.sh", "release"],
        cd: File.cwd!(),
        env: [{"RALPH_MAX_CYCLES", "0"}],
        stderr_to_stdout: true
      )

    assert status == 0
    assert output =~ "running release Ralph loop"
    assert output =~ "release Ralph loop complete"
  end
end
