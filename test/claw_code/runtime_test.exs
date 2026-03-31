defmodule ClawCode.RuntimeTest do
  use ExUnit.Case, async: true

  alias ClawCode.{Runtime, SessionStore}

  test "bootstrap renders routed context and local tools" do
    output = Runtime.bootstrap("review MCP tool", limit: 5, native: false)
    assert output =~ "# Bootstrap"
    assert output =~ "Routed Matches"
    assert output =~ "Local Tools"
  end

  test "chat persists a missing-provider result when credentials are absent" do
    result =
      Runtime.chat("hello from claw",
        provider: "generic",
        base_url: nil,
        api_key: nil,
        model: nil,
        native: false
      )

    assert result.stop_reason == "missing_provider_config"
    assert File.exists?(result.session_path)
    assert result.requirements == SessionStore.requirements_ledger()

    session =
      result.session_path
      |> Path.basename(".json")
      |> then(&SessionStore.load(&1, root: Path.dirname(result.session_path)))

    assert session["requirements"] == SessionStore.requirements_ledger()
  end
end
