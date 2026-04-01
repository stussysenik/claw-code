defmodule ClawCode.QAScriptTest do
  use ExUnit.Case, async: false

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
end
