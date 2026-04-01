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
    assert receipt.policy["decision"] == "blocked"
    assert receipt.policy["rule"] == "blocked_shell_prefix"
    assert receipt.policy["blocked_prefix"] == "rm"
    assert receipt.policy["allow_shell"] == true
  end

  test "write_file reports disabled policy in the receipt" do
    assert {:error, message, receipt} =
             Builtin.execute_with_receipt(
               "write_file",
               %{"path" => "tmp/example.txt", "content" => "hello"},
               allow_write: false
             )

    assert message =~ "write_file is disabled"
    assert receipt.status == "blocked"
    assert receipt.exit_status == "blocked"
    assert receipt.policy["decision"] == "blocked"
    assert receipt.policy["rule"] == "write_disabled"
    assert receipt.policy["allow_write"] == false
  end

  test "sexp_outline summarizes top-level forms through the Common Lisp adapter" do
    source = """
    (defpackage :demo)
    (defun hello (name)
      (format t "Hello, ~A" name))
    """

    assert {:ok, output, receipt} =
             Builtin.execute_with_receipt("sexp_outline", %{"source" => source})

    assert output =~ "forms=2"
    assert output =~ "1. defpackage demo"
    assert output =~ "2. defun hello"
    assert receipt.tool == "sexp_outline"
    assert receipt.kind == "runtime"
    assert receipt.runtime == "common_lisp"
    assert receipt.status == "ok"
    assert receipt.invocation == "sexp_outline max_forms=20"
    assert receipt.source_bytes == byte_size(source)
  end
end
