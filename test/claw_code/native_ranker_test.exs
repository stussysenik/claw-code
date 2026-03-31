defmodule ClawCode.NativeRankerTest do
  use ExUnit.Case, async: false

  alias ClawCode.{Entry, NativeRanker}

  test "native ranker returns ranked entries when zig is installed" do
    if NativeRanker.available?() do
      entries = [
        %Entry{
          kind: :command,
          name: "review",
          source_hint: "commands/review.ts",
          responsibility: "Review code"
        },
        %Entry{
          kind: :tool,
          name: "MCPTool",
          source_hint: "tools/MCPTool.ts",
          responsibility: "Fetch MCP resources"
        }
      ]

      ranked = NativeRanker.rank("review MCP tool", entries)
      assert Enum.any?(ranked, &(&1.name == "review" and &1.score > 0))
      assert Enum.any?(ranked, &(&1.name == "MCPTool" and &1.score > 0))
    end
  end
end
