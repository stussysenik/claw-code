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

  test "safe_rank reports invalid output without raising" do
    entries = [
      %Entry{
        kind: :command,
        name: "review",
        source_hint: "commands/review.ts",
        responsibility: "Review code"
      }
    ]

    assert {:error, {:invalid_output, "bad-output"}} =
             NativeRanker.safe_rank("review", entries,
               ensure_compiled: fn -> :ok end,
               runner: fn _tmp_path -> {"bad-output\n", 0} end
             )
  end
end
