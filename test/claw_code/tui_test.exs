defmodule ClawCode.TUITest do
  use ExUnit.Case, async: true

  alias ClawCode.TUI
  alias ClawCode.TUI.State
  alias ClawCode.SessionStore

  test "render includes session list and selected transcript" do
    sessions = [
      %{
        "id" => "session-a",
        "updated_at" => "2026-03-31T19:00:00Z",
        "stop_reason" => "completed",
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
        "stop_reason" => "completed",
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
    assert output =~ "filter=all limit=8"
    assert output =~ "session-a"
    assert output =~ "assistant: world"
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

  test "open aliases select latest running and failed sessions" do
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
end
