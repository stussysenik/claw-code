defmodule ClawCode.CLITest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias ClawCode.{CLI, SessionStore}

  test "summary command renders app summary" do
    output = capture_io(fn -> assert CLI.run(["summary"]) == 0 end)
    assert output =~ "# Claw Code Elixir"
  end

  test "doctor renders provider diagnostics" do
    output = capture_io(fn -> assert CLI.run(["doctor"]) == 0 end)

    assert output =~ "# Doctor"
    assert output =~ "- configured:"
    assert output =~ "- request_url:"
    assert output =~ "- missing:"
  end

  test "doctor accepts provider flags" do
    output =
      capture_io(fn ->
        assert CLI.run(["doctor", "--provider", "kimi", "--api-key", "test-key"]) == 0
      end)

    assert output =~ "- provider: kimi"
    assert output =~ "- api_key: tes**key"
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
        assert CLI.run(["resume-session", session_id, "--provider", "generic", "resume me"]) == 1
      end)

    assert output =~ "Session id: #{session_id}"
    assert output =~ "Stop reason: missing_provider_config"
  end

  test "sessions command lists recent sessions" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-sessions-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)

    SessionStore.save(%{id: "session-a", prompt: "hello", output: "world", messages: []},
      root: root
    )

    SessionStore.save(%{id: "session-b", prompt: "hi", output: "there", messages: []}, root: root)

    output =
      capture_io(fn ->
        assert CLI.run(["sessions", "--limit", "5"]) == 0
      end)

    assert output =~ "# Sessions"
    assert output =~ "session-a"
    assert output =~ "session-b"
  end

  test "load-session can render messages and receipts" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-load-session-detail-test")
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
          id: "session-detail",
          prompt: "hello",
          output: "world",
          stop_reason: "completed",
          messages: [
            %{"role" => "system", "content" => "seed context"},
            %{"role" => "user", "content" => "inspect repo"}
          ],
          tool_receipts: [
            %{
              "started_at" => "2026-03-31T18:00:00Z",
              "tool_name" => "shell",
              "status" => "ok",
              "exit_status" => 0,
              "output" => "git status"
            }
          ]
        },
        root: root
      )

    session_id = Path.basename(path, ".json")

    output =
      capture_io(fn ->
        assert CLI.run(["load-session", session_id, "--show-messages", "--show-receipts"]) == 0
      end)

    assert output =~ "Messages:"
    assert output =~ "1. system: seed context"
    assert output =~ "Receipts:"
    assert output =~ "shell status=ok exit=0"
  end

  test "load-session returns 1 for a missing session" do
    output =
      capture_io(fn ->
        assert CLI.run(["load-session", "missing-session"]) == 1
      end)

    assert output =~ "Session not found: missing-session"
  end

  test "chat returns 1 when provider configuration is missing" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "generic", "hello"]) == 1
      end)

    assert output =~ "Stop reason: missing_provider_config"
  end

  test "chat rejects an unknown provider" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "kimii", "hello"]) == 1
      end)

    assert output =~ "Unknown provider: kimii"
  end

  test "chat rejects invalid switches" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "kimi", "--api-keyy", "test-key", "hello"]) == 1
      end)

    assert output =~ "Unknown options: --api-keyy"
  end
end
