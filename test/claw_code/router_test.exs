defmodule ClawCode.RouterTest do
  use ExUnit.Case, async: true

  alias ClawCode.Router

  defmodule FailingNativeRanker do
    def available?, do: true
    def safe_rank(_prompt, _entries), do: {:error, :boom}
  end

  test "routes review and mcp prompts across commands and tools" do
    matches = Router.route("review MCP tool", limit: 5, native: false)

    assert Enum.any?(matches, &(&1.kind == :command and String.downcase(&1.name) == "review"))
    assert Enum.any?(matches, &(&1.kind == :tool and String.downcase(&1.name) == "mcptool"))
  end

  test "falls back to pure ranking when native ranking fails" do
    matches =
      Router.route("review MCP tool",
        limit: 5,
        native: true,
        native_ranker: FailingNativeRanker
      )

    assert Enum.any?(matches, &(&1.kind == :command and String.downcase(&1.name) == "review"))
    assert Enum.any?(matches, &(&1.kind == :tool and String.downcase(&1.name) == "mcptool"))
  end
end
