defmodule ClawCode.HostTest do
  use ExUnit.Case, async: true

  alias ClawCode.Host

  test "python runtime surfaces stderr and exit status" do
    assert {:error, output, receipt} =
             Host.run_runtime_with_receipt(
               :python,
               "import sys; sys.stderr.write('python-boom\\n'); sys.stderr.flush(); raise SystemExit(7)"
             )

    assert output =~ "python-boom"
    assert receipt.status == "error"
    assert receipt.exit_status == 7
    assert receipt.runtime == "python"
    assert receipt.invocation =~ "-c"
  end

  test "python runtime respects timeout_ms" do
    assert {:error, output, receipt} =
             Host.run_runtime_with_receipt(
               :python,
               "import time; time.sleep(1)",
               timeout_ms: 100
             )

    assert output =~ "timed out after 100ms"
    assert receipt.status == "timeout"
    assert receipt.exit_status == "timeout"
    assert receipt.runtime == "python"
  end

  test "lua runtime surfaces stderr and exit status" do
    assert {:error, output, receipt} =
             Host.run_runtime_with_receipt(
               :lua,
               "io.stderr:write('lua-boom\\n'); io.stderr:flush(); os.exit(9)"
             )

    assert output =~ "lua-boom"
    assert receipt.status == "error"
    assert receipt.exit_status == 9
    assert receipt.runtime == "lua"
    assert receipt.invocation =~ "-e"
  end

  test "lua runtime respects timeout_ms" do
    assert {:error, output, receipt} =
             Host.run_runtime_with_receipt(
               :lua,
               "local deadline = os.clock() + 1 while os.clock() < deadline do end",
               timeout_ms: 100
             )

    assert output =~ "timed out after 100ms"
    assert receipt.status == "timeout"
    assert receipt.exit_status == "timeout"
    assert receipt.runtime == "lua"
  end

  test "common lisp runtime surfaces stderr and exit status" do
    runtime = Host.runtime(:common_lisp)

    assert {:error, output, receipt} =
             Host.run_runtime_with_receipt(:common_lisp, lisp_exit_code(runtime.engine))

    assert output =~ "lisp-boom"
    assert receipt.status == "error"
    assert receipt.exit_status == 11
    assert receipt.runtime == "common_lisp"
  end

  test "common lisp runtime respects timeout_ms" do
    assert {:error, output, receipt} =
             Host.run_runtime_with_receipt(
               :common_lisp,
               lisp_sleep_code(),
               timeout_ms: 100
             )

    assert output =~ "timed out after 100ms"
    assert receipt.status == "timeout"
    assert receipt.exit_status == "timeout"
    assert receipt.runtime == "common_lisp"
  end

  defp lisp_exit_code("sbcl") do
    "(progn (format *error-output* \"lisp-boom~%\") (finish-output *error-output*) (sb-ext:exit :code 11))"
  end

  defp lisp_exit_code("clisp") do
    "(progn (format *error-output* \"lisp-boom~%\") (finish-output *error-output*) (ext:quit 11))"
  end

  defp lisp_sleep_code do
    "(sleep 1)"
  end
end
