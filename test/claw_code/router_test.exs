defmodule ClawCode.RouterTest do
  use ExUnit.Case, async: true

  alias ClawCode.Router

  test "routes review and mcp prompts across commands and tools" do
    matches = Router.route("review MCP tool", limit: 5, native: false)

    assert Enum.any?(matches, &(&1.kind == :command and String.downcase(&1.name) == "review"))
    assert Enum.any?(matches, &(&1.kind == :tool and String.downcase(&1.name) == "mcptool"))
  end
end
