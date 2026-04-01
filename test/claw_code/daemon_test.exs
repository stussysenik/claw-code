defmodule ClawCode.DaemonTest do
  use ExUnit.Case, async: false

  alias ClawCode.{Daemon, Runtime, SessionStore}

  test "status reflects daemon lifecycle" do
    daemon_root = tmp_path("daemon-status")
    session_root = tmp_path("daemon-status-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    assert {:ok, %{"status" => "stopped"}} = Daemon.status(daemon_root: daemon_root)

    task = start_daemon(daemon_root, session_root: session_root)

    assert {:ok, %{"status" => "running"} = status} = Daemon.status(daemon_root: daemon_root)
    assert status["session_root"] == session_root
    assert is_binary(status["started_at"])

    assert {:ok, %{"status" => "stopping"}} = Daemon.stop(daemon_root: daemon_root)
    assert :ok = Task.await(task, 2_000)
    assert {:ok, %{"status" => "stopped"}} = Daemon.status(daemon_root: daemon_root)
  end

  test "chat runs through the daemon and persists the session" do
    daemon_root = tmp_path("daemon-chat")
    session_root = tmp_path("daemon-chat-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "daemon reply"}}]
        })
      ])

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    assert {:ok, %Runtime.Result{} = result} =
             Daemon.chat("hello from daemon",
               daemon_root: daemon_root,
               session_root: session_root,
               provider: "generic",
               base_url: base_url,
               api_key: "test-key",
               model: "test-model",
               native: false
             )

    assert result.stop_reason == "completed"
    assert result.output == "daemon reply"
    assert File.exists?(result.session_path)

    session = SessionStore.load(result.session_id, root: session_root)
    assert session["output"] == "daemon reply"
    assert get_in(session, ["run_state", "status"]) == "idle"
  end

  test "chat uses the daemon session_root when the client omits it" do
    daemon_root = tmp_path("daemon-default-root")
    session_root = tmp_path("daemon-default-root-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [
            %{"message" => %{"role" => "assistant", "content" => "daemon default root"}}
          ]
        })
      ])

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    assert {:ok, %Runtime.Result{} = result} =
             Daemon.chat("hello from daemon",
               daemon_root: daemon_root,
               provider: "generic",
               base_url: base_url,
               api_key: "test-key",
               model: "test-model",
               native: false
             )

    assert Path.dirname(result.session_path) == session_root

    assert SessionStore.load(result.session_id, root: session_root)["output"] ==
             "daemon default root"
  end

  test "chat rejects a conflicting client session_root instead of silently forking state" do
    daemon_root = tmp_path("daemon-root-authority")
    session_root = tmp_path("daemon-root-authority-sessions")
    conflicting_root = tmp_path("daemon-root-authority-conflict")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(conflicting_root)

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    assert {:error, message} =
             Daemon.chat("hello from daemon",
               daemon_root: daemon_root,
               session_root: conflicting_root,
               provider: "generic",
               base_url: "http://127.0.0.1:1/v1",
               api_key: "test-key",
               model: "test-model",
               native: false
             )

    assert message =~ "Daemon session root mismatch"
    assert message =~ session_root
    assert message =~ conflicting_root
    assert SessionStore.count(root: session_root) == 0
    assert SessionStore.count(root: conflicting_root) == 0
  end

  test "cancel_session cancels an active daemon run" do
    daemon_root = tmp_path("daemon-cancel")
    session_root = tmp_path("daemon-cancel-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    {base_url, listener, server} =
      start_stub_server([
        {Jason.encode!(%{
           "choices" => [%{"message" => %{"role" => "assistant", "content" => "late reply"}}]
         }), 500}
      ])

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    session_id = "daemon-cancel-session"

    chat_task =
      Task.async(fn ->
        Daemon.chat("slow prompt",
          daemon_root: daemon_root,
          session_root: session_root,
          provider: "generic",
          base_url: base_url,
          api_key: "test-key",
          model: "test-model",
          session_id: session_id,
          native: false
        )
      end)

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: session_root) do
               {:ok, session} -> get_in(session, ["run_state", "status"]) == "running"
               :error -> false
             end
           end)

    assert {:ok, %{"stop_reason" => "cancelled"}} =
             Daemon.cancel_session(session_id,
               daemon_root: daemon_root,
               session_root: session_root
             )

    assert {:ok, %Runtime.Result{} = result} = Task.await(chat_task, 2_000)
    assert result.stop_reason == "cancelled"
  end

  test "cancel_session rejects a conflicting client session_root" do
    daemon_root = tmp_path("daemon-cancel-root-authority")
    session_root = tmp_path("daemon-cancel-root-authority-sessions")
    conflicting_root = tmp_path("daemon-cancel-root-authority-conflict")
    session_id = "daemon-root-authority-running"

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)
    File.rm_rf(conflicting_root)

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    SessionStore.save(
      %{
        id: session_id,
        prompt: "hello",
        messages: [],
        stop_reason: "running",
        run_state: %{"status" => "running", "started_at" => "2026-04-01T00:00:00Z"}
      },
      root: session_root
    )

    assert {:error, message} =
             Daemon.cancel_session(session_id,
               daemon_root: daemon_root,
               session_root: conflicting_root
             )

    assert message =~ "Daemon session root mismatch"
    assert message =~ session_root
    assert message =~ conflicting_root

    assert get_in(SessionStore.load(session_id, root: session_root), ["run_state", "status"]) ==
             "running"

    assert SessionStore.count(root: conflicting_root) == 0
  end

  test "chat resumes an existing session through the daemon" do
    daemon_root = tmp_path("daemon-resume")
    session_root = tmp_path("daemon-resume-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "first reply"}}]
        }),
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "second reply"}}]
        })
      ])

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    session_id = "daemon-resume-session"

    assert {:ok, %Runtime.Result{} = first} =
             Daemon.chat("first prompt",
               daemon_root: daemon_root,
               session_root: session_root,
               provider: "generic",
               base_url: base_url,
               api_key: "test-key",
               model: "test-model",
               session_id: session_id,
               native: false
             )

    assert {:ok, %Runtime.Result{} = second} =
             Daemon.chat("second prompt",
               daemon_root: daemon_root,
               session_root: session_root,
               provider: "generic",
               base_url: base_url,
               api_key: "test-key",
               model: "test-model",
               session_id: session_id,
               native: false
             )

    assert first.session_id == session_id
    assert second.session_id == session_id
    assert first.session_path == second.session_path

    session = SessionStore.load(session_id, root: session_root)
    assert second.turns == 2
    assert length(session["messages"]) == 5
    assert Enum.at(session["messages"], 3)["content"] == "second prompt"
    assert List.last(session["messages"])["content"] == "second reply"
  end

  test "chat resumes an existing session after daemon restart" do
    daemon_root = tmp_path("daemon-restart")
    session_root = tmp_path("daemon-restart-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    {base_url, listener, server} =
      start_stub_server([
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "first reply"}}]
        }),
        Jason.encode!(%{
          "choices" => [%{"message" => %{"role" => "assistant", "content" => "second reply"}}]
        })
      ])

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
      File.rm_rf(daemon_root)
      File.rm_rf(session_root)
    end)

    session_id = "daemon-restart-session"

    assert {:ok, %Runtime.Result{} = first} =
             Daemon.chat("first prompt",
               daemon_root: daemon_root,
               session_root: session_root,
               provider: "generic",
               base_url: base_url,
               api_key: "test-key",
               model: "test-model",
               session_id: session_id,
               native: false
             )

    assert {:ok, %{"status" => "stopping"}} = Daemon.stop(daemon_root: daemon_root)
    assert :ok = Task.await(task, 2_000)
    assert {:ok, %{"status" => "stopped"}} = Daemon.status(daemon_root: daemon_root)

    restarted = start_daemon(daemon_root, session_root: session_root)

    assert {:ok, %Runtime.Result{} = second} =
             Daemon.chat("second prompt",
               daemon_root: daemon_root,
               session_root: session_root,
               provider: "generic",
               base_url: base_url,
               api_key: "test-key",
               model: "test-model",
               session_id: session_id,
               native: false
             )

    assert first.session_id == session_id
    assert second.session_id == session_id
    assert first.session_path == second.session_path

    session = SessionStore.load(session_id, root: session_root)
    assert second.turns == 2
    assert length(session["messages"]) == 5
    assert Enum.at(session["messages"], 3)["content"] == "second prompt"
    assert List.last(session["messages"])["content"] == "second reply"

    Process.unlink(task.pid)
    Process.unlink(restarted.pid)
  end

  test "stop returns an error when the daemon never stops" do
    daemon_root = tmp_path("daemon-stop-timeout")
    session_root = tmp_path("daemon-stop-timeout-sessions")

    File.rm_rf(daemon_root)
    File.mkdir_p!(daemon_root)

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        {:packet, 4},
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listener)
    token = "fake-daemon-token"

    File.write!(
      Path.join(daemon_root, "daemon.json"),
      Jason.encode_to_iodata!(%{
        "host" => "127.0.0.1",
        "port" => port,
        "token" => token,
        "pid" => "fake-daemon",
        "version" => "0.1.0",
        "started_at" => "2026-04-01T00:00:00Z",
        "session_root" => session_root
      })
    )

    server =
      spawn_link(fn ->
        fake_daemon_loop(listener, token)
      end)

    on_exit(fn ->
      send(server, :stop)
      :gen_tcp.close(listener)
      File.rm_rf(daemon_root)
    end)

    assert {:ok, %{"status" => "running"}} = Daemon.status(daemon_root: daemon_root)

    assert {:error, :stop_timeout} =
             Daemon.stop(
               daemon_root: daemon_root,
               daemon_wait_attempts: 2,
               daemon_poll_interval_ms: 1
             )
  end

  test "serve replaces stale daemon metadata with a live daemon" do
    daemon_root = tmp_path("daemon-stale")
    session_root = tmp_path("daemon-stale-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)
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
        "session_root" => session_root
      })
    )

    assert {:ok, %{"status" => "stale"}} = Daemon.status(daemon_root: daemon_root)

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    assert {:ok, %{"status" => "running"} = status} = Daemon.status(daemon_root: daemon_root)
    assert status["session_root"] == session_root
    refute status["token"] == "stale-token"
  end

  test "daemon startup reconciles abandoned running sessions before health reporting" do
    daemon_root = tmp_path("daemon-health")
    session_root = tmp_path("daemon-health-sessions")

    File.rm_rf(daemon_root)
    File.rm_rf(session_root)

    SessionStore.save(
      %{
        id: "session-running",
        stop_reason: "running",
        provider: %{"provider" => "glm", "model" => "GLM-4.7"},
        run_state: %{"status" => "running", "started_at" => "2026-04-01T00:01:00Z"},
        output: "still running",
        messages: [],
        tool_receipts: []
      },
      root: session_root
    )

    SessionStore.save(
      %{
        id: "session-failed",
        stop_reason: "provider_error",
        provider: %{"provider" => "generic", "model" => "test-model"},
        run_state: %{
          "status" => "idle",
          "finished_at" => "2026-04-01T00:03:10Z",
          "last_stop_reason" => "provider_error"
        },
        output: "provider request failed with status 401: unauthorized",
        messages: [],
        tool_receipts: [
          %{
            "tool_name" => "shell",
            "status" => "ok",
            "duration_ms" => 42,
            "started_at" => "2026-04-01T00:03:00Z"
          }
        ]
      },
      root: session_root
    )

    SessionStore.save(
      %{
        id: "session-recovered",
        stop_reason: "run_interrupted",
        provider: %{"provider" => "nim", "model" => "meta/llama-3.1-8b-instruct"},
        run_state: %{
          "status" => "idle",
          "finished_at" => "2026-04-01T00:05:00Z",
          "last_stop_reason" => "run_interrupted"
        },
        output: "Session run interrupted during recovery.",
        messages: [],
        tool_receipts: []
      },
      root: session_root
    )

    task = start_daemon(daemon_root, session_root: session_root)

    on_exit(fn ->
      _ = Daemon.stop(daemon_root: daemon_root)
      if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)
    end)

    assert {:ok, %{"status" => "running", "health" => health} = status} =
             Daemon.status(daemon_root: daemon_root)

    assert status["session_root"] == session_root
    assert health["signals"] == ["failed", "partially_recovered"]

    assert health["counts"] == %{
             "completed" => 0,
             "failed" => 1,
             "invalid" => 0,
             "recovered" => 2,
             "running" => 0,
             "total" => 3
           }

    assert is_nil(health["latest_running"])
    assert get_in(health, ["latest_failed", "id"]) == "session-failed"
    assert get_in(health, ["latest_failed", "detail"]) =~ "unauthorized"
    assert get_in(health, ["latest_failed", "last_receipt", "tool"]) == "shell"
    assert get_in(health, ["latest_failed", "last_receipt", "duration_ms"]) == 42
    assert get_in(health, ["latest_recovered", "id"]) == "session-running"
    assert get_in(health, ["latest_recovered", "stop_reason"]) == "run_interrupted"

    persisted = SessionStore.load("session-running", root: session_root)
    assert persisted["stop_reason"] == "run_interrupted"
    assert persisted["run_state"]["status"] == "idle"
    assert persisted["output"] == "still running"
  end

  defp start_daemon(daemon_root, opts) do
    task =
      Task.async(fn ->
        :ok = Daemon.serve(Keyword.put(opts, :daemon_root, daemon_root))
      end)

    assert wait_until(fn ->
             match?({:ok, %{"status" => "running"}}, Daemon.status(daemon_root: daemon_root))
           end)

    task
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

  defp fake_daemon_loop(listener, token) do
    receive do
      :stop ->
        :ok
    after
      0 ->
        case :gen_tcp.accept(listener) do
          {:ok, socket} ->
            {:ok, payload} = :gen_tcp.recv(socket, 0, 1_000)
            {:ok, request} = Jason.decode(payload)

            response =
              cond do
                request["token"] != token ->
                  %{"ok" => false, "error" => "unauthorized"}

                request["method"] == "ping" ->
                  %{
                    "ok" => true,
                    "result" => %{
                      "pid" => "fake-daemon",
                      "server_time" => "2026-04-01T00:00:00Z"
                    }
                  }

                request["method"] == "shutdown" ->
                  %{"ok" => true, "result" => %{"status" => "stopping"}}

                true ->
                  %{"ok" => false, "error" => "unknown_method"}
              end

            :ok = :gen_tcp.send(socket, Jason.encode!(response))
            :gen_tcp.close(socket)
            fake_daemon_loop(listener, token)

          {:error, :closed} ->
            :ok
        end
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

  defp wait_until(fun, attempts \\ 40)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: false

  defp tmp_path(label) do
    Path.join(System.tmp_dir!(), "claw-code-#{label}-#{SessionStore.new_id()}")
  end
end
