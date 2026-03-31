defmodule ClawCode.TUITest do
  use ExUnit.Case, async: true

  alias ClawCode.TUI
  alias ClawCode.TUI.State

  test "render includes session list and selected transcript" do
    state = %State{
      opts: [provider: "generic", tools: false],
      daemon_status: %{"status" => "running"},
      doctor: %{
        provider: "generic",
        model: %{value: "test-model"},
        tool_policy: :disabled
      },
      sessions: [
        %{
          "id" => "session-a",
          "updated_at" => "2026-03-31T19:00:00Z",
          "stop_reason" => "completed",
          "messages" => [%{"role" => "user", "content" => "hello"}],
          "tool_receipts" => []
        }
      ],
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
    assert output =~ "session-a"
    assert output =~ "assistant: world"
  end

  test "open command selects a session by index" do
    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{provider: "generic", model: %{value: "test-model"}, tool_policy: :auto},
      sessions: [
        %{"id" => "session-a", "messages" => [], "tool_receipts" => []},
        %{"id" => "session-b", "messages" => [], "tool_receipts" => []}
      ],
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
      sessions: [],
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
      sessions: [],
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
      sessions: [],
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
    state = %State{
      opts: [],
      daemon_status: %{"status" => "running"},
      doctor: %{
        provider: "generic",
        model: %{value: "test-model"},
        base_url: %{value: nil},
        tool_policy: :auto
      },
      sessions: [
        %{"id" => "session-a", "messages" => [], "tool_receipts" => []},
        %{"id" => "session-b", "messages" => [], "tool_receipts" => []},
        %{"id" => "session-c", "messages" => [], "tool_receipts" => []}
      ],
      session_root: System.tmp_dir!(),
      selected_session_id: "session-b",
      selected_session: nil
    }

    {:continue, next_state} = TUI.apply_command(state, "next")
    assert next_state.selected_session_id == "session-c"

    {:continue, prev_state} = TUI.apply_command(next_state, "prev")
    assert prev_state.selected_session_id == "session-b"
  end
end
