defmodule ClawCode.TUITest do
  use ExUnit.Case, async: false

  alias ClawCode.{Daemon, Runtime, TUI}
  alias ClawCode.TUI.State
  alias ClawCode.SessionStore

  test "render includes session list and selected transcript" do
    sessions = [
      %{
        "id" => "session-a",
        "updated_at" => "2026-03-31T19:00:00Z",
        "provider" => %{"provider" => "glm", "model" => "glm-4.7"},
        "prompt" => "inspect repo state",
        "output" => "world",
        "stop_reason" => "completed",
        "run_state" => %{
          "status" => "idle",
          "finished_at" => "2026-03-31T19:01:00Z",
          "last_stop_reason" => "completed"
        },
        "messages" => [%{"role" => "user", "content" => "hello"}],
        "tool_receipts" => []
      }
    ]

    state = %State{
      opts: [provider: "generic", tools: false],
      daemon_status: %{"status" => "running"},
      doctor: %{
        provider: "generic",
        model: %{value: "test-model"},
        tool_policy: :disabled
      },
      all_sessions: sessions,
      sessions: sessions,
      session_filter: :all,
      session_limit: 8,
      session_root: "/tmp/claw",
      selected_session_id: "session-a",
      selected_session: %{
        "id" => "session-a",
        "provider" => %{"provider" => "glm", "model" => "glm-4.7"},
        "prompt" => "inspect repo state",
        "output" => "world",
        "stop_reason" => "completed",
        "run_state" => %{
          "status" => "idle",
          "finished_at" => "2026-03-31T19:01:00Z",
          "last_stop_reason" => "completed"
        },
        "messages" => [
          %{"role" => "user", "content" => "hello"},
          %{"role" => "assistant", "content" => "world"}
        ],
        "tool_receipts" => []
      },
      notice: "Connected to daemon."
    }

    output = TUI.render(state)

    assert output =~ "# Claw Code TUI"
    assert output =~ "provider=generic"
    assert output =~ "selected=1/1"
    assert output =~ "runs=running:0 completed:1 failed:0"
    assert output =~ "filter=all limit=8 query=-"
    assert output =~ "watch=off follow=off"
    assert output =~ "transcript_query=- hit=-"
    assert output =~ "selected_run=idle last_stop=completed"
    assert output =~ "selected_receipt=none"
    assert output =~ "started=- finished=2026-03-31T19:01:00Z last_stop=completed"
    assert output =~ "provider=glm model=glm-4.7"
    assert output =~ "prompt=inspect repo state"
    assert output =~ "output=world"
    assert output =~ "last_receipt=none"
    assert output =~ "session-a 2026-03-31T19:00:00Z run=idle stop=completed provider=glm"
    assert output =~ "assistant: world"
  end

  test "render surfaces running counts and last receipt summary" do
    running_session = %{
      "id" => "session-running",
      "provider" => %{"provider" => "nim", "model" => "nvidia/model"},
      "prompt" => "keep monitoring",
      "output" => "still working",
      "stop_reason" => "running",
      "run_state" => %{
        "status" => "running",
        "started_at" => "2026-03-31T20:00:00Z"
      },
      "messages" => [%{"role" => "assistant", "content" => "working"}],
      "tool_receipts" => [
        %{
          "tool_name" => "shell",
          "status" => "ok",
          "duration_ms" => 42,
          "started_at" => "2026-03-31T20:00:02Z"
        }
      ]
    }

    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [
        running_session,
        %{
          "id" => "session-completed",
          "stop_reason" => "completed",
          "messages" => [],
          "tool_receipts" => []
        },
        %{
          "id" => "session-failed",
          "stop_reason" => "provider_error",
          "messages" => [],
          "tool_receipts" => []
        }
      ],
      sessions: [running_session],
      session_filter: :running,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: "session-running",
      selected_session: running_session
    }

    output = TUI.render(state)

    assert output =~ "runs=running:1 completed:1 failed:1"
    assert output =~ "selected_run=running since=2026-03-31T20:00:00Z"
    assert output =~ "selected_receipt=shell:ok:42ms"
    assert output =~ "provider=nim model=nvidia/model"
    assert output =~ "prompt=keep monitoring"
    assert output =~ "output=still working"
    assert output =~ "last_receipt=shell ok 42ms 2026-03-31T20:00:02Z"
    assert output =~ "1. shell ok 42ms 2026-03-31T20:00:02Z"
  end

  test "watch command updates refresh cadence" do
    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, on_state} = TUI.apply_command(state, "watch on")
    assert on_state.watch_interval_ms == 2_000
    assert on_state.notice =~ "2s"
    assert TUI.render(on_state) =~ "watch=2s"

    {:continue, custom_state} = TUI.apply_command(on_state, "watch 5")
    assert custom_state.watch_interval_ms == 5_000
    assert custom_state.notice =~ "5s"

    {:continue, off_state} = TUI.apply_command(custom_state, "watch off")
    assert off_state.watch_interval_ms == nil
    assert off_state.notice =~ "disabled"

    {:continue, invalid_state} = TUI.apply_command(off_state, "watch nope")
    assert invalid_state.watch_interval_ms == nil
    assert invalid_state.notice =~ "positive integer"
  end

  test "follow command updates tracked target" do
    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, follow_state} = TUI.apply_command(state, "follow running")
    assert follow_state.follow_target == "running"
    assert follow_state.notice =~ "Follow set to running"
    assert TUI.render(follow_state) =~ "follow=running"

    {:continue, active_state} = TUI.apply_command(follow_state, "follow active")
    assert active_state.follow_target == "active"
    assert active_state.notice =~ "Follow set to active"

    {:continue, off_state} = TUI.apply_command(follow_state, "follow off")
    assert off_state.follow_target == nil
    assert off_state.notice =~ "Follow disabled"
  end

  test "refresh follows the running session target when one appears" do
    root = Path.join(System.tmp_dir!(), "claw-code-tui-follow-#{SessionStore.new_id()}")
    File.rm_rf(root)

    on_exit(fn -> File.rm_rf(root) end)

    SessionStore.save(%{id: "session-completed", stop_reason: "completed", messages: []},
      root: root
    )

    state =
      TUI.build_state(
        [provider: "generic"],
        %{"status" => "running", "session_root" => root},
        nil
      )

    {:continue, follow_state} = TUI.apply_command(state, "follow running")
    assert follow_state.follow_target == "running"
    assert follow_state.selected_session_id == "session-completed"

    SessionStore.save(
      %{
        id: "session-running",
        stop_reason: "running",
        run_state: %{"status" => "running", "started_at" => "2026-03-31T23:20:00Z"},
        messages: [%{"role" => "assistant", "content" => "still working"}]
      },
      root: root
    )

    {:continue, refreshed_state} = TUI.apply_command(follow_state, "refresh")
    assert refreshed_state.follow_target == "running"
    assert refreshed_state.selected_session_id == "session-running"
    assert refreshed_state.selected_session["id"] == "session-running"
  end

  test "focus active configures a running-session monitoring preset" do
    root = Path.join(System.tmp_dir!(), "claw-code-tui-focus-#{SessionStore.new_id()}")
    File.rm_rf(root)

    on_exit(fn -> File.rm_rf(root) end)

    SessionStore.save(%{id: "session-completed", stop_reason: "completed", messages: []},
      root: root
    )

    SessionStore.save(
      %{
        id: "session-running",
        stop_reason: "running",
        run_state: %{"status" => "running", "started_at" => "2026-03-31T23:30:00Z"},
        messages: [%{"role" => "assistant", "content" => "still working"}]
      },
      root: root
    )

    state =
      TUI.build_state(
        [provider: "generic"],
        %{"status" => "running", "session_root" => root},
        nil
      )

    {:continue, focused_state} = TUI.apply_command(state, "focus active")
    assert focused_state.session_filter == :running
    assert focused_state.follow_target == "running"
    assert focused_state.watch_interval_ms == 1_000
    assert focused_state.selected_session_id == "session-running"
    assert focused_state.notice =~ "active sessions"
    assert TUI.render(focused_state) =~ "watch=1s follow=running"

    {:continue, reset_state} = TUI.apply_command(focused_state, "focus all")
    assert reset_state.session_filter == :all
    assert reset_state.follow_target == nil
    assert reset_state.watch_interval_ms == nil
    assert reset_state.notice =~ "all sessions"
  end

  test "cancel active cancels the running daemon session" do
    daemon_root = tmp_path("tui-cancel-active")
    session_root = tmp_path("tui-cancel-active-sessions")

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
      File.rm_rf(daemon_root)
      File.rm_rf(session_root)
    end)

    session_id = "tui-cancel-active-session"

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

    state =
      TUI.build_state(
        [daemon_root: daemon_root, session_root: session_root, provider: "generic"],
        %{"status" => "running", "session_root" => session_root},
        nil
      )

    {:continue, next_state} = TUI.apply_command(state, "cancel active")

    assert next_state.notice =~ "Cancelled #{session_id}."

    assert wait_until(fn ->
             case SessionStore.fetch(session_id, root: session_root) do
               {:ok, session} -> session["stop_reason"] == "cancelled"
               :error -> false
             end
           end)

    assert {:ok, %Runtime.Result{} = result} = Task.await(chat_task, 2_000)
    assert result.stop_reason == "cancelled"
  end

  test "cancel selected reports when no session is selected" do
    state = %State{
      opts: [daemon_root: tmp_path("tui-cancel-selected")],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [%{"id" => "session-a", "messages" => [], "tool_receipts" => []}],
      sessions: [%{"id" => "session-a", "messages" => [], "tool_receipts" => []}],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "cancel selected")
    assert next_state.notice =~ "No session selected"
  end

  test "open command selects a session by index" do
    sessions = [
      %{"id" => "session-a", "messages" => [], "tool_receipts" => []},
      %{"id" => "session-b", "messages" => [], "tool_receipts" => []}
    ]

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: sessions,
      sessions: sessions,
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: "session-a",
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "open 2")

    assert next_state.selected_session_id == "session-b"
    assert next_state.notice =~ "Opened session session-b"
  end

  test "open active selects the running session" do
    sessions = [
      %{
        "id" => "session-completed",
        "stop_reason" => "completed",
        "messages" => [],
        "tool_receipts" => []
      },
      %{
        "id" => "session-running",
        "stop_reason" => "running",
        "run_state" => %{"status" => "running"},
        "messages" => [],
        "tool_receipts" => []
      }
    ]

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: sessions,
      sessions: sessions,
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: "session-completed",
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "open active")
    assert next_state.selected_session_id == "session-running"
    assert next_state.notice =~ "Opened session session-running"
  end

  test "tools command updates local tool mode" do
    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "unknown", "session_root" => System.tmp_dir!()},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, off_state} = TUI.apply_command(state, "tools off")
    assert off_state.opts[:tools] == false
    assert off_state.notice =~ "disabled"

    {:continue, auto_state} = TUI.apply_command(off_state, "tools auto")
    refute Keyword.has_key?(auto_state.opts, :tools)
    assert auto_state.notice =~ "auto"
  end

  test "provider and model commands update local inference configuration" do
    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "unknown", "session_root" => System.tmp_dir!()},
      doctor: %{
        provider: "generic",
        model: %{value: "test-model"},
        base_url: %{value: nil},
        tool_policy: :auto
      },
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, provider_state} = TUI.apply_command(state, "provider kimi")
    assert provider_state.opts[:provider] == "kimi"
    assert provider_state.doctor.provider == "kimi"

    {:continue, model_state} = TUI.apply_command(provider_state, "model kimi-k2.5")
    assert model_state.opts[:model] == "kimi-k2.5"
    assert model_state.doctor.model.value == "kimi-k2.5"

    {:continue, default_provider_state} = TUI.apply_command(model_state, "provider default")
    refute Keyword.has_key?(default_provider_state.opts, :provider)
    assert default_provider_state.notice =~ "default"

    {:continue, default_model_state} = TUI.apply_command(default_provider_state, "model default")
    refute Keyword.has_key?(default_model_state.opts, :model)
    assert default_model_state.notice =~ "default"
  end

  test "base-url commands update and clear the local endpoint" do
    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "unknown", "session_root" => System.tmp_dir!()},
      doctor: %{
        provider: "generic",
        model: %{value: "test-model"},
        base_url: %{value: nil},
        tool_policy: :auto
      },
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, url_state} = TUI.apply_command(state, "base-url http://127.0.0.1:1234/v1")
    assert url_state.opts[:base_url] == "http://127.0.0.1:1234/v1"
    assert url_state.doctor.base_url.value == "http://127.0.0.1:1234/v1"

    {:continue, cleared_state} = TUI.apply_command(url_state, "clear base-url")
    refute Keyword.has_key?(cleared_state.opts, :base_url)
    assert cleared_state.notice =~ "cleared"
  end

  test "probe command reports missing provider configuration" do
    state = %State{
      opts: [provider: "generic"],
      daemon_status: %{"status" => "unknown", "session_root" => System.tmp_dir!()},
      doctor: %{
        provider: "generic",
        model: %{value: nil},
        base_url: %{value: nil},
        tool_policy: :auto
      },
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "probe")
    assert next_state.notice =~ "Probe missing_config"
  end

  test "resume requires a selected session" do
    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [],
      sessions: [],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: nil,
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "resume keep going")
    assert next_state.notice =~ "No session selected"
  end

  test "resume target alias without a prompt is rejected" do
    sessions = [
      %{
        "id" => "session-a",
        "stop_reason" => "completed",
        "messages" => [],
        "tool_receipts" => []
      }
    ]

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: sessions,
      sessions: sessions,
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: "session-a",
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "resume latest")
    assert next_state.notice =~ "Prompt is required"
  end

  test "next and prev commands move the selected session" do
    sessions = [
      %{"id" => "session-a", "messages" => [], "tool_receipts" => []},
      %{"id" => "session-b", "messages" => [], "tool_receipts" => []},
      %{"id" => "session-c", "messages" => [], "tool_receipts" => []}
    ]

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{
        provider: "generic",
        model: %{value: "test-model"},
        base_url: %{value: nil},
        tool_policy: :auto
      },
      all_sessions: sessions,
      sessions: sessions,
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: "session-b",
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "next")
    assert next_state.selected_session_id == "session-c"

    {:continue, prev_state} = TUI.apply_command(next_state, "prev")
    assert prev_state.selected_session_id == "session-b"
  end

  test "open aliases select latest running completed and failed sessions" do
    all_sessions = [
      %{
        "id" => "session-latest",
        "stop_reason" => "completed",
        "messages" => [],
        "tool_receipts" => []
      },
      %{
        "id" => "session-running",
        "run_state" => %{"status" => "running"},
        "stop_reason" => nil,
        "messages" => [],
        "tool_receipts" => []
      },
      %{
        "id" => "session-failed",
        "stop_reason" => "provider_error",
        "messages" => [],
        "tool_receipts" => []
      }
    ]

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: all_sessions,
      sessions: all_sessions,
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      selected_session_id: "session-latest",
      selected_session: nil
    }

    {:continue, latest_state} = TUI.apply_command(state, "open latest")
    assert latest_state.selected_session_id == "session-latest"

    {:continue, running_state} = TUI.apply_command(state, "open running")
    assert running_state.selected_session_id == "session-running"

    {:continue, completed_state} = TUI.apply_command(state, "open completed")
    assert completed_state.selected_session_id == "session-latest"

    {:continue, latest_completed_state} = TUI.apply_command(state, "open latest-completed")
    assert latest_completed_state.selected_session_id == "session-latest"

    {:continue, failed_state} = TUI.apply_command(state, "open failed")
    assert failed_state.selected_session_id == "session-failed"
  end

  test "filter and limit commands rebuild the visible session list" do
    root = Path.join(System.tmp_dir!(), "claw-code-tui-filter-#{SessionStore.new_id()}")
    File.rm_rf(root)

    on_exit(fn -> File.rm_rf(root) end)

    SessionStore.save(%{id: "session-completed", stop_reason: "completed", messages: []},
      root: root
    )

    SessionStore.save(
      %{
        id: "session-running",
        stop_reason: nil,
        run_state: %{"status" => "running"},
        messages: []
      },
      root: root
    )

    SessionStore.save(%{id: "session-failed", stop_reason: "provider_error", messages: []},
      root: root
    )

    state =
      TUI.build_state(
        [provider: "generic"],
        %{"status" => "running", "session_root" => root},
        nil
      )

    {:continue, filtered_state} = TUI.apply_command(state, "filter failed")
    assert filtered_state.session_filter == :failed
    assert Enum.all?(filtered_state.sessions, &(&1["stop_reason"] == "provider_error"))

    {:continue, limited_state} = TUI.apply_command(filtered_state, "limit 2")
    assert limited_state.session_limit == 2
    assert length(limited_state.all_sessions) == 2
  end

  test "find and clear find rebuild the visible session list" do
    root = Path.join(System.tmp_dir!(), "claw-code-tui-find-#{SessionStore.new_id()}")
    File.rm_rf(root)

    on_exit(fn -> File.rm_rf(root) end)

    SessionStore.save(%{id: "session-alpha", prompt: "review alpha repo", messages: []},
      root: root
    )

    SessionStore.save(%{id: "session-beta", prompt: "inspect beta service", messages: []},
      root: root
    )

    state =
      TUI.build_state(
        [provider: "generic"],
        %{"status" => "running", "session_root" => root},
        nil
      )

    {:continue, found_state} = TUI.apply_command(state, "find beta")
    assert found_state.session_query == "beta"
    assert length(found_state.all_sessions) == 2
    assert Enum.map(found_state.sessions, & &1["id"]) == ["session-beta"]

    {:continue, cleared_state} = TUI.apply_command(found_state, "clear find")
    assert cleared_state.session_query == nil
    assert length(cleared_state.sessions) == 2
  end

  test "find-msg and clear find-msg update transcript search state" do
    session = %{
      "id" => "session-a",
      "messages" => [
        %{"role" => "user", "content" => "inspect alpha"},
        %{"role" => "assistant", "content" => "beta response"},
        %{"role" => "user", "content" => "beta follow-up"}
      ],
      "tool_receipts" => []
    }

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [session],
      sessions: [session],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      transcript_query: nil,
      transcript_match_index: 0,
      selected_session_id: "session-a",
      selected_session: session
    }

    {:continue, found_state} = TUI.apply_command(state, "find-msg beta")
    assert found_state.transcript_query == "beta"
    assert found_state.transcript_match_index == 0
    assert found_state.notice =~ "Hit 1/2"

    output = TUI.render(found_state)
    assert output =~ "transcript_query=beta hit=1/2"
    assert output =~ "match 1/2 for \"beta\""

    {:continue, cleared_state} = TUI.apply_command(found_state, "clear find-msg")
    assert cleared_state.transcript_query == nil
    assert cleared_state.transcript_match_index == 0
  end

  test "next-hit and prev-hit navigate transcript matches" do
    session = %{
      "id" => "session-a",
      "messages" => [
        %{"role" => "user", "content" => "alpha"},
        %{"role" => "assistant", "content" => "beta one"},
        %{"role" => "user", "content" => "gamma"},
        %{"role" => "assistant", "content" => "beta two"}
      ],
      "tool_receipts" => []
    }

    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      all_sessions: [session],
      sessions: [session],
      session_filter: :all,
      session_limit: 8,
      session_root: System.tmp_dir!(),
      transcript_query: "beta",
      transcript_match_index: 0,
      selected_session_id: "session-a",
      selected_session: session
    }

    {:continue, next_state} = TUI.apply_command(state, "next-hit")
    assert next_state.transcript_match_index == 1
    assert next_state.notice =~ "2/2"

    {:continue, bounded_state} = TUI.apply_command(next_state, "next-hit")
    assert bounded_state.transcript_match_index == 1
    assert bounded_state.notice =~ "last transcript hit"

    {:continue, prev_state} = TUI.apply_command(next_state, "prev-hit")
    assert prev_state.transcript_match_index == 0
    assert prev_state.notice =~ "1/2"
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
