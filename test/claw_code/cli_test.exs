defmodule ClawCode.CLITest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias ClawCode.{CLI, Daemon, Runtime, SessionStore}

  test "summary command renders app summary" do
    output = capture_io(fn -> assert CLI.run(["summary"]) == 0 end)
    assert output =~ "# Claw Code Elixir"
  end

  test "doctor renders provider diagnostics" do
    output = capture_io(fn -> assert CLI.run(["doctor"]) == 0 end)

    assert output =~ "# Doctor"
    assert output =~ "- configured:"
    assert output =~ "- auth_mode:"
    assert output =~ "- tool_support:"
    assert output =~ "- input_modalities:"
    assert output =~ "- request_url:"
    assert output =~ "- missing:"
  end

  test "doctor can render json" do
    output =
      capture_io(fn ->
        assert CLI.run(["doctor", "--provider", "generic", "--no-tools", "--json"]) == 0
      end)

    payload = Jason.decode!(output)
    assert payload["provider"] == "generic"
    assert payload["tool_policy"] == "disabled"
    assert payload["input_modalities"] == ["text", "image"]
  end

  test "doctor accepts provider flags" do
    output =
      capture_io(fn ->
        assert CLI.run(["doctor", "--provider", "kimi", "--api-key", "test-key"]) == 0
      end)

    assert output =~ "- provider: kimi"
    assert output =~ "- api_key: tes**key"
  end

  test "doctor accepts a custom api key header" do
    output =
      capture_io(fn ->
        assert CLI.run([
                 "doctor",
                 "--provider",
                 "generic",
                 "--api-key",
                 "test-key",
                 "--api-key-header",
                 "api-key"
               ]) == 0
      end)

    assert output =~ "- api_key_header: api-key"
  end

  test "providers renders the supported provider matrix" do
    output = capture_io(fn -> assert CLI.run(["providers"]) == 0 end)

    assert output =~ "# Providers"
    assert output =~ "## generic"
    assert output =~ "## glm"
    assert output =~ "## kimi"
    assert output =~ "## nim"
    assert output =~ "- input_modalities: text, image"
    assert output =~ "- setup_template: .env.local.example"
  end

  test "providers can render json" do
    output =
      capture_io(fn ->
        assert CLI.run(["providers", "--json"]) == 0
      end)

    payload = Jason.decode!(output)
    assert payload["setup_template"] == ".env.local.example"
    assert Enum.map(payload["providers"], & &1["provider"]) == ["generic", "glm", "nim", "kimi"]
    assert Enum.all?(payload["providers"], &(&1["input_modalities"] == ["text", "image"]))
  end

  test "doctor renders explicit tool policy" do
    output =
      capture_io(fn ->
        assert CLI.run(["doctor", "--provider", "generic", "--no-tools"]) == 0
      end)

    assert output =~ "- tool_policy: disabled"
  end

  test "doctor renders explicit shell and write access" do
    output =
      capture_io(fn ->
        assert CLI.run(["doctor", "--provider", "generic", "--allow-shell", "--allow-write"]) == 0
      end)

    assert output =~ "- shell_access: enabled"
    assert output =~ "- write_access: enabled"
  end

  test "probe renders provider connectivity" do
    responses = [
      Jason.encode!(%{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "probe-ok"}}]
      })
    ]

    {base_url, listener, server} = start_stub_server(responses)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "probe",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--model",
                 "local-model",
                 "Reply with OK."
               ]) == 0
      end)

    assert output =~ "# Probe"
    assert output =~ "- status: ok"
    assert output =~ "- request_modalities: text"
    assert output =~ "- request_mode: standard"
    assert output =~ "- response: probe-ok"
  end

  test "probe can render json failures for missing provider config" do
    output =
      capture_io(fn ->
        assert CLI.run(["probe", "--provider", "generic", "--json"]) == 1
      end)

    payload = Jason.decode!(output)
    assert payload["status"] == "missing_config"
    assert payload["provider"] == "generic"
  end

  test "probe renders text failures for missing provider config without crashing" do
    output =
      capture_io(fn ->
        assert CLI.run(["probe", "--provider", "generic"]) == 1
      end)

    assert output =~ "# Probe"
    assert output =~ "- status: missing_config"
    assert output =~ "- request_modalities: text"
    assert output =~ "- request_mode: standard"
    assert output =~ "- error: missing provider configuration"
  end

  test "probe renders multimodal request modalities when image input is provided" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-probe-image-#{SessionStore.new_id()}")
    File.rm_rf(root)
    File.mkdir_p!(root)

    on_exit(fn -> File.rm_rf(root) end)

    image_path = write_png(root, "probe-image.png")

    {base_url, listener, server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [%{"message" => %{"role" => "assistant", "content" => "probe-image-ok"}}]
          })
        ],
        capture_requests: true
      )

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "probe",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--model",
                 "local-model",
                 "--image",
                 image_path,
                 "describe this image"
               ]) == 0
      end)

    assert output =~ "# Probe"
    assert output =~ "- status: ok"
    assert output =~ "- request_modalities: text, image"

    assert_receive {:request, request}, 1_000
    assert request =~ "\"type\":\"image_url\""
    assert request =~ "data:image/png;base64,"
  end

  test "probe fails explicitly when an image input path is missing" do
    output =
      capture_io(fn ->
        assert CLI.run([
                 "probe",
                 "--provider",
                 "generic",
                 "--base-url",
                 "http://127.0.0.1:1/v1",
                 "--model",
                 "local-model",
                 "--image",
                 "missing-image.png",
                 "describe this image"
               ]) == 1
      end)

    assert output =~ "# Probe"
    assert output =~ "- status: invalid_input"
    assert output =~ "- request_modalities: text, image"
    assert output =~ "Image input does not exist"
  end

  test "chat accepts explicit tool policy flags" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--no-tools", "--provider", "generic", "hello"]) == 1
      end)

    assert output =~ "Stop reason: missing_provider_config"
  end

  test "chat fails explicitly when an image input path is missing" do
    output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--provider",
                 "generic",
                 "--base-url",
                 "http://127.0.0.1:1/v1",
                 "--model",
                 "local-model",
                 "--image",
                 "missing-image.png",
                 "describe this image"
               ]) == 1
      end)

    assert output =~ "Stop reason: invalid_image_input"
    assert output =~ "Image input does not exist"
  end

  test "load-session renders multimodal user content in message view" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-load-session-multimodal-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end

      File.rm_rf(root)
    end)

    Application.put_env(:claw_code, :session_root, root)

    path =
      SessionStore.save(
        %{
          id: "session-multimodal",
          messages: [
            %{
              "role" => "user",
              "content" => [
                %{"type" => "text", "text" => "inspect screenshot"},
                %{
                  "type" => "input_image",
                  "path" => "/tmp/example-diagram.png",
                  "mime_type" => "image/png"
                }
              ]
            }
          ]
        },
        root: root
      )

    session_id = Path.basename(path, ".json")

    output =
      capture_io(fn ->
        assert CLI.run(["load-session", session_id, "--show-messages"]) == 0
      end)

    assert output =~ "Messages:"
    assert output =~ "1. user: inspect screenshot [image:example-diagram.png]"
  end

  test "daemon status reports stopped when no daemon is running" do
    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-status-#{SessionStore.new_id()}")

    previous_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_root)
      end

      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(daemon_root)

    output =
      capture_io(fn ->
        assert CLI.run(["daemon", "status"]) == 0
      end)

    assert output =~ "# Daemon"
    assert output =~ "- status: stopped"
  end

  test "daemon status reports stale metadata" do
    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-stale-#{SessionStore.new_id()}")

    previous_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_root)
      end

      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.mkdir_p!(daemon_root)

    File.write!(
      Path.join(daemon_root, "daemon.json"),
      Jason.encode_to_iodata!(%{
        "host" => "127.0.0.1",
        "port" => 65_000,
        "token" => "stale-token",
        "pid" => "99999",
        "version" => "0.1.0",
        "started_at" => "2026-03-31T00:00:00Z",
        "session_root" => Path.join(daemon_root, "sessions")
      })
    )

    output =
      capture_io(fn ->
        assert CLI.run(["daemon", "status"]) == 0
      end)

    assert output =~ "# Daemon"
    assert output =~ "- status: stale"
  end

  test "daemon status reports recovered abandoned running sessions after startup" do
    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-health-#{SessionStore.new_id()}")

    session_root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-cli-daemon-health-sessions-#{SessionStore.new_id()}"
      )

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    SessionStore.save(
      %{
        id: "session-running",
        stop_reason: "running",
        provider: %{"provider" => "glm", "model" => "GLM-4.7"},
        run_state: %{"status" => "running", "started_at" => "2026-04-01T00:01:00Z"},
        messages: []
      },
      root: session_root
    )

    SessionStore.save(
      %{
        id: "session-failed",
        stop_reason: "provider_error",
        provider: %{"provider" => "generic", "model" => "test-model"},
        output: "provider request failed with status 401: unauthorized",
        run_state: %{"status" => "idle", "last_stop_reason" => "provider_error"},
        tool_receipts: [
          %{
            "tool_name" => "shell",
            "status" => "ok",
            "duration_ms" => 42,
            "started_at" => "2026-04-01T00:03:00Z"
          }
        ],
        messages: []
      },
      root: session_root
    )

    SessionStore.save(
      %{
        id: "session-recovered",
        stop_reason: "run_interrupted",
        provider: %{"provider" => "nim", "model" => "meta/llama-3.1-8b-instruct"},
        output: "Session run interrupted during recovery.",
        run_state: %{"status" => "idle", "last_stop_reason" => "run_interrupted"},
        messages: []
      },
      root: session_root
    )

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root, session_root: session_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run(["daemon", "status", "--daemon-root", daemon_root]) == 0
      end)

    assert output =~ "# Daemon"
    assert output =~ "- status: running"
    assert output =~ "- health: failed, partially_recovered"
    assert output =~ "- sessions: total=3 running=0 completed=0 failed=1 recovered=2 invalid=0"
    assert output =~ "- latest_failed: session-failed provider=generic stop=provider_error"
    assert output =~ "detail=provider request failed with status 401: unauthorized"
    assert output =~ "- latest_failed_receipt: shell ok 42ms 2026-04-01T00:03:00Z"
    assert output =~ "- latest_recovered: session-running provider=glm stop=run_interrupted"
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

    SessionStore.save(
      %{
        id: "session-a",
        prompt: "hello",
        output: "world",
        provider: %{provider: "glm", model: "glm-4.7"},
        messages: []
      },
      root: root
    )

    SessionStore.save(
      %{
        id: "session-b",
        prompt: "hi",
        output: "there",
        provider: %{provider: "kimi", model: "kimi-k2.5"},
        messages: []
      },
      root: root
    )

    output =
      capture_io(fn ->
        assert CLI.run(["sessions", "--limit", "5"]) == 0
      end)

    assert output =~ "# Sessions"
    assert output =~ "session-a"
    assert output =~ "session-b"
    assert output =~ "run=idle"
    assert output =~ "provider=glm"
    assert output =~ "output=there"
  end

  test "sessions command can render json" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-sessions-json-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)

    SessionStore.save(%{id: "session-json", prompt: "hello", output: "world", messages: []},
      root: root
    )

    output =
      capture_io(fn ->
        assert CLI.run(["sessions", "--limit", "5", "--json"]) == 0
      end)

    payload = Jason.decode!(output)
    assert [%{"id" => "session-json"} | _rest] = payload["sessions"]
  end

  test "sessions command can filter by query" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-sessions-query-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)

    SessionStore.save(%{id: "session-alpha", prompt: "review alpha repo", messages: []},
      root: root
    )

    SessionStore.save(%{id: "session-beta", prompt: "inspect beta service", messages: []},
      root: root
    )

    output =
      capture_io(fn ->
        assert CLI.run(["sessions", "--limit", "5", "--query", "beta"]) == 0
      end)

    assert output =~ "session-beta"
    refute output =~ "session-alpha"
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
          provider: %{"provider" => "glm", "model" => "glm-4.7"},
          run_state: %{
            "status" => "idle",
            "started_at" => "2026-04-01T00:10:00Z",
            "finished_at" => "2026-04-01T00:10:04Z",
            "last_stop_reason" => "completed"
          },
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
    assert output =~ "run=idle"
    assert output =~ "provider=glm"
    assert output =~ "model=glm-4.7"
    assert output =~ "started=2026-04-01T00:10:00Z"
    assert output =~ "finished=2026-04-01T00:10:04Z"
    assert output =~ "prompt=hello"
    assert output =~ "output=world"
  end

  test "load-session renders permission snapshots and blocked receipt policy details" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-load-session-permissions-test")
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
          id: "session-permissions",
          prompt: "dangerous shell request",
          output: "blocked",
          stop_reason: "completed",
          provider: %{"provider" => "glm", "model" => "glm-4.7"},
          permissions: %{
            "tool_policy" => "enabled",
            "allow_shell" => true,
            "allow_write" => false,
            "deny_tools" => [],
            "deny_prefixes" => []
          },
          run_state: %{"status" => "idle"},
          messages: [
            %{"role" => "user", "content" => "run rm -rf"}
          ],
          tool_receipts: [
            %{
              "started_at" => "2026-04-01T00:00:00Z",
              "tool_name" => "shell",
              "status" => "blocked",
              "exit_status" => "blocked",
              "output" => "shell command blocked by policy: rm -rf /tmp/example",
              "policy" => %{
                "decision" => "blocked",
                "rule" => "blocked_shell_prefix",
                "blocked_prefix" => "rm",
                "allow_shell" => true
              }
            }
          ]
        },
        root: root
      )

    session_id = Path.basename(path, ".json")

    output =
      capture_io(fn ->
        assert CLI.run(["load-session", session_id, "--show-receipts"]) == 0
      end)

    assert output =~ "permissions=tool_policy=enabled shell=enabled write=disabled"
    assert output =~ "policy=blocked_shell_prefix:rm"
  end

  test "load-session accepts latest-completed alias" do
    root = Path.join(System.tmp_dir!(), "claw-code-cli-load-session-alias-test")
    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)

    SessionStore.save(%{id: "session-running", run_state: %{"status" => "running"}, messages: []},
      root: root
    )

    SessionStore.save(%{id: "session-completed", stop_reason: "completed", messages: []},
      root: root
    )

    output =
      capture_io(fn ->
        assert CLI.run(["load-session", "latest-completed"]) == 0
      end)

    assert output =~ "session-completed"
  end

  test "cancel-session stops an active run" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-cli-cancel-session-test-#{SessionStore.new_id()}")

    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)
    File.rm_rf(root)

    {base_url, listener, server} =
      start_stub_server([
        {Jason.encode!(%{
           "choices" => [
             %{
               "message" => %{
                 "role" => "assistant",
                 "content" => "late reply"
               }
             }
           ]
         }), 500}
      ])

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    session_id = "cli-cancel-session"

    task =
      Task.async(fn ->
        Runtime.chat("slow prompt",
          provider: "generic",
          base_url: base_url,
          api_key: "test-key",
          model: "test-model",
          session_id: session_id,
          session_root: root,
          native: false
        )
      end)

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: root) do
               {:ok, session} -> get_in(session, ["run_state", "status"]) == "running"
               :error -> false
             end
           end)

    output =
      capture_io(fn ->
        assert CLI.run(["cancel-session", session_id]) == 0
      end)

    assert output =~ "Cancelled session in this runtime: #{session_id}"

    result = Task.await(task, 2_000)
    assert result.stop_reason == "cancelled"
  end

  test "chat can use the daemon transport" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-chat-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "daemon reply"}}]
        })
      ])

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "hello"
               ]) == 0
      end)

    assert output =~ "# Chat Result"
    assert output =~ "Stop reason: completed"
    assert output =~ "daemon reply"
  end

  test "daemon chat returns 1 when the client tries to override the daemon session_root" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-root-#{SessionStore.new_id()}")

    conflicting_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-root-conflict-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-root-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(conflicting_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(conflicting_root)
    File.rm_rf(daemon_root)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root, session_root: session_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--session-root",
                 conflicting_root,
                 "--provider",
                 "generic",
                 "--base-url",
                 "http://127.0.0.1:1/v1",
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "hello"
               ]) == 1
      end)

    assert output =~ "Daemon session root mismatch"
    assert output =~ session_root
    assert output =~ conflicting_root
  end

  test "daemon-backed chat forwards repeated image inputs to the provider boundary" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-image-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-image-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)
    File.mkdir_p!(session_root)

    image_one = write_png(session_root, "image-one.png")
    image_two = write_png(session_root, "image-two.png")

    {base_url, listener, server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "role" => "assistant",
                  "content" => "vision reply"
                }
              }
            ]
          })
        ],
        capture_requests: true
      )

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root, session_root: session_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "--image",
                 image_one,
                 "--image",
                 image_two,
                 "describe both images"
               ]) == 0
      end)

    assert output =~ "Stop reason: completed"
    assert output =~ "vision reply"

    assert_receive {:request, request}, 1_000
    assert length(Regex.scan(~r/data:image\/png;base64,/, request)) == 2
    assert request =~ "\"type\":\"image_url\""
    assert request =~ "describe both images"
  end

  test "daemon-backed chat can split reasoning and vision backbones" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-vision-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-vision-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)
    File.mkdir_p!(session_root)

    image_path = write_png(session_root, "vision-split.png")

    {vision_base_url, vision_listener, vision_server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "role" => "assistant",
                  "content" => "a red warning dialog with two buttons"
                }
              }
            ]
          })
        ],
        capture_requests: true
      )

    {base_url, listener, server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "role" => "assistant",
                  "content" => "reasoned answer"
                }
              }
            ]
          })
        ],
        capture_requests: true
      )

    on_exit(fn ->
      send(vision_server, :stop)
      :gen_tcp.close(vision_listener)
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root, session_root: session_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--provider",
                 "glm",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "glm-test-key",
                 "--model",
                 "GLM-5.1",
                 "--vision-provider",
                 "kimi",
                 "--vision-base-url",
                 vision_base_url,
                 "--vision-api-key",
                 "kimi-test-key",
                 "--vision-model",
                 "kimi-k2.5",
                 "--image",
                 image_path,
                 "describe this screenshot"
               ]) == 0
      end)

    assert output =~ "Stop reason: completed"
    assert output =~ "Vision backbone: kimi/kimi-k2.5"
    assert output =~ "reasoned answer"

    assert_receive {:request, vision_request}, 1_000
    assert vision_request =~ "\"model\":\"kimi-k2.5\""
    assert vision_request =~ "\"type\":\"image_url\""

    assert_receive {:request, primary_request}, 1_000
    assert primary_request =~ "\"model\":\"GLM-5.1\""

    assert primary_request =~
             "Vision context from kimi/kimi-k2.5: a red warning dialog with two buttons"

    refute primary_request =~ "\"type\":\"image_url\""
  end

  test "daemon chat forwards explicit no-tools policy" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-tools-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-tools-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    {base_url, listener, server} =
      start_stub_server(
        [
          Jason.encode!(%{
            "choices" => [
              %{
                "message" => %{
                  "role" => "assistant",
                  "content" => "daemon no-tools reply"
                }
              }
            ]
          })
        ],
        capture_requests: true
      )

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "--no-tools",
                 "inspect the repo and list relevant files"
               ]) == 0
      end)

    assert output =~ "Stop reason: completed"
    assert output =~ "daemon no-tools reply"
    assert_receive {:request, request}, 1_000
    refute request =~ "\"tools\""
  end

  test "resume-session can use the daemon transport" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-resume-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-resume-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "first reply"}}]
        }),
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "second reply"}}]
        })
      ])

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    session_id = "cli-daemon-resume"

    first_output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "--session-id",
                 session_id,
                 "first prompt"
               ]) == 0
      end)

    second_output =
      capture_io(fn ->
        assert CLI.run([
                 "resume-session",
                 session_id,
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "second prompt"
               ]) == 0
      end)

    assert first_output =~ "Stop reason: completed"
    assert second_output =~ "Stop reason: completed"
    assert second_output =~ "second reply"

    session = SessionStore.load(session_id, root: session_root)
    assert length(session["messages"]) == 5
    assert Enum.at(session["messages"], 3)["content"] == "second prompt"
    assert List.last(session["messages"])["content"] == "second reply"
  end

  test "resume-session accepts latest alias on the daemon transport" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-resume-latest-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-cli-daemon-resume-latest-meta-#{SessionStore.new_id()}"
      )

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "first reply"}}]
        }),
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "latest reply"}}]
        })
      ])

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    first_output =
      capture_io(fn ->
        assert CLI.run([
                 "chat",
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "--session-id",
                 "cli-daemon-resume-latest",
                 "first prompt"
               ]) == 0
      end)

    second_output =
      capture_io(fn ->
        assert CLI.run([
                 "resume-session",
                 "latest",
                 "--daemon",
                 "--provider",
                 "generic",
                 "--base-url",
                 base_url,
                 "--api-key",
                 "test-key",
                 "--model",
                 "test-model",
                 "second prompt"
               ]) == 0
      end)

    assert first_output =~ "Stop reason: completed"
    assert second_output =~ "Stop reason: completed"
    assert second_output =~ "latest reply"

    session = SessionStore.load("cli-daemon-resume-latest", root: session_root)
    assert length(session["messages"]) == 5
    assert Enum.at(session["messages"], 3)["content"] == "second prompt"
  end

  test "cancel-session can use the daemon transport" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-cancel-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-cancel-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    {base_url, listener, server} =
      start_stub_server([
        {Jason.encode!(%{
           "choices" => [%{"message" => %{"role" => "assistant", "content" => "late reply"}}]
         }), 500}
      ])

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
    end)

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    session_id = "cli-daemon-cancel"

    task =
      Task.async(fn ->
        Daemon.chat("hello",
          provider: "generic",
          base_url: base_url,
          api_key: "test-key",
          model: "test-model",
          session_id: session_id,
          session_root: session_root,
          daemon_root: daemon_root,
          native: false
        )
      end)

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: session_root) do
               {:ok, session} -> get_in(session, ["run_state", "status"]) == "running"
               :error -> false
             end
           end)

    output =
      capture_io(fn ->
        assert CLI.run(["cancel-session", session_id, "--daemon"]) == 0
      end)

    assert output =~ "Cancelled session via daemon: #{session_id}"
    assert {:ok, result} = Task.await(task, 2_000)
    assert result.stop_reason == "cancelled"
  end

  test "cancel-session via daemon returns 1 when the session is idle" do
    session_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-idle-#{SessionStore.new_id()}")

    daemon_root =
      Path.join(System.tmp_dir!(), "claw-code-cli-daemon-idle-meta-#{SessionStore.new_id()}")

    previous_session_root = Application.get_env(:claw_code, :session_root)
    previous_daemon_root = Application.get_env(:claw_code, :daemon_root)

    on_exit(fn ->
      if is_nil(previous_session_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_session_root)
      end

      if is_nil(previous_daemon_root) do
        Application.delete_env(:claw_code, :daemon_root)
      else
        Application.put_env(:claw_code, :daemon_root, previous_daemon_root)
      end

      case Daemon.stop(daemon_root: daemon_root) do
        {:ok, _result} -> :ok
        _other -> :ok
      end

      File.rm_rf(session_root)
      File.rm_rf(daemon_root)
    end)

    Application.put_env(:claw_code, :session_root, session_root)
    Application.put_env(:claw_code, :daemon_root, daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(daemon_root)

    SessionStore.save(
      %{id: "idle-daemon-session", prompt: "hello", output: "world", messages: []},
      root: session_root
    )

    {:ok, daemon_task} =
      Task.start_link(fn ->
        Daemon.serve(daemon_root: daemon_root, session_root: session_root)
      end)

    on_exit(fn ->
      if Process.alive?(daemon_task), do: Process.exit(daemon_task, :kill)
    end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    output =
      capture_io(fn ->
        assert CLI.run(["cancel-session", "idle-daemon-session", "--daemon"]) == 1
      end)

    assert output =~ "Session is not running in the daemon: idle-daemon-session"
  end

  test "cancel-session returns 1 when a session is not active" do
    root =
      Path.join(
        System.tmp_dir!(),
        "claw-code-cli-cancel-not-running-test-#{SessionStore.new_id()}"
      )

    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end
    end)

    Application.put_env(:claw_code, :session_root, root)
    File.rm_rf(root)

    SessionStore.save(%{id: "not-running", prompt: "hello", output: "world", messages: []},
      root: root
    )

    output =
      capture_io(fn ->
        assert CLI.run(["cancel-session", "not-running"]) == 1
      end)

    assert output =~ "Session is not running in this runtime: not-running"
  end

  test "load-session returns 1 for a missing session" do
    output =
      capture_io(fn ->
        assert CLI.run(["load-session", "missing-session"]) == 1
      end)

    assert output =~ "Session not found: missing-session"
  end

  test "load-session returns 1 with a local invalid-session message for corrupted state" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-cli-invalid-load-test-#{SessionStore.new_id()}")

    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end

      File.rm_rf(root)
    end)

    Application.put_env(:claw_code, :session_root, root)
    File.rm_rf(root)
    File.mkdir_p!(root)
    File.write!(Path.join(root, "broken-cli-session.json"), "{not-json")

    output =
      capture_io(fn ->
        assert CLI.run(["load-session", "broken-cli-session"]) == 1
      end)

    assert output =~ "Session state is invalid for broken-cli-session"
    assert output =~ Path.join(root, "broken-cli-session.json")
  end

  test "resume-session returns 1 with a local invalid-session message for corrupted state" do
    root =
      Path.join(System.tmp_dir!(), "claw-code-cli-invalid-resume-test-#{SessionStore.new_id()}")

    previous_root = Application.get_env(:claw_code, :session_root)

    on_exit(fn ->
      if is_nil(previous_root) do
        Application.delete_env(:claw_code, :session_root)
      else
        Application.put_env(:claw_code, :session_root, previous_root)
      end

      File.rm_rf(root)
    end)

    Application.put_env(:claw_code, :session_root, root)
    File.rm_rf(root)
    File.mkdir_p!(root)
    File.write!(Path.join(root, "broken-cli-resume.json"), "{not-json")

    output =
      capture_io(fn ->
        assert CLI.run([
                 "resume-session",
                 "broken-cli-resume",
                 "--provider",
                 "generic",
                 "continue"
               ]) ==
                 1
      end)

    assert output =~ "Session state is invalid for broken-cli-resume"
  end

  test "chat returns 1 when provider configuration is missing" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "generic", "hello"]) == 1
      end)

    assert output =~ "Stop reason: missing_provider_config"
  end

  test "chat can render json result" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "generic", "--json", "hello"]) == 1
      end)

    payload = Jason.decode!(output)
    assert payload["provider"] == "generic"
    assert payload["stop_reason"] == "missing_provider_config"
  end

  test "chat rejects an unknown provider" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "kimii", "hello"]) == 1
      end)

    assert output =~ "Unknown provider: kimii"
  end

  test "chat rejects an unknown vision provider" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "glm", "--vision-provider", "kimii", "hello"]) == 1
      end)

    assert output =~ "Unknown vision provider: kimii"
  end

  test "chat renders json errors when requested" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "kimii", "--json", "hello"]) == 1
      end)

    payload = Jason.decode!(output)
    assert payload["error"] =~ "Unknown provider: kimii"
  end

  test "chat rejects invalid switches" do
    output =
      capture_io(fn ->
        assert CLI.run(["chat", "--provider", "kimi", "--api-keyy", "test-key", "hello"]) == 1
      end)

    assert output =~ "Unknown options: --api-keyy"
  end

  defp start_stub_server(responses, opts \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listener)
    request_caller = self()
    capture_requests? = Keyword.get(opts, :capture_requests, false)

    server =
      spawn_link(fn ->
        serve_responses(listener, responses, request_caller, capture_requests?)
      end)

    {"http://127.0.0.1:#{port}/v1", listener, server}
  end

  defp serve_responses(listener, responses, request_caller, capture_requests?) do
    Enum.each(responses, fn response ->
      {body, delay_ms} =
        case response do
          {body, delay_ms} -> {body, delay_ms}
          body -> {body, 0}
        end

      {:ok, socket} = :gen_tcp.accept(listener)
      {:ok, request} = read_request(socket, "")

      if capture_requests? do
        send(request_caller, {:request, request})
      end

      Process.sleep(delay_ms)
      :ok = :gen_tcp.send(socket, http_response(body))
      :gen_tcp.close(socket)
    end)

    receive do
      :stop -> :ok
    after
      100 -> :ok
    end
  end

  defp read_request(socket, acc) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} ->
        buffer = acc <> chunk

        case String.split(buffer, "\r\n\r\n", parts: 2) do
          [headers, body] ->
            content_length =
              headers
              |> String.split("\r\n")
              |> Enum.find_value(0, fn line ->
                case String.split(line, ":", parts: 2) do
                  ["Content-Length", value] -> String.trim(value) |> String.to_integer()
                  _other -> nil
                end
              end)

            if byte_size(body) >= content_length do
              {:ok, buffer}
            else
              read_request(socket, buffer)
            end

          [_partial] ->
            read_request(socket, buffer)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_response(body) do
    [
      "HTTP/1.1 200 OK\r\n",
      "content-type: application/json\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n\r\n",
      body
    ]
    |> IO.iodata_to_binary()
  end

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: false

  defp write_png(root, name) do
    path = Path.join(root, name)

    File.write!(
      path,
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+X3cAAAAASUVORK5CYII="
      )
    )

    path
  end
end
