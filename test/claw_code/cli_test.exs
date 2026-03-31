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
    assert output =~ "run=idle"
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
    assert output =~ "run=idle"
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

  defp start_stub_server(responses) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    server =
      spawn_link(fn ->
        serve_responses(listener, responses)
      end)

    {"http://127.0.0.1:#{port}/v1", listener, server}
  end

  defp serve_responses(listener, responses) do
    Enum.each(responses, fn response ->
      {body, delay_ms} =
        case response do
          {body, delay_ms} -> {body, delay_ms}
          body -> {body, 0}
        end

      {:ok, socket} = :gen_tcp.accept(listener)
      {:ok, _request} = read_request(socket, "")
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
end
