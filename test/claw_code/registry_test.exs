defmodule ClawCode.RegistryTest do
  use ExUnit.Case, async: true

  alias ClawCode.{Permissions, Registry}

  test "loads mirrored command and tool registries" do
    stats = Registry.stats()
    assert stats.commands >= 150
    assert stats.tools >= 100
  end

  test "find filters command and tool entries" do
    assert Enum.any?(Registry.find(:command, "review"), &(&1.name == "review"))
    assert Enum.any?(Registry.find(:tool, "MCP"), &(String.downcase(&1.name) == "mcptool"))
  end

  test "permission context filters tools" do
    filtered = Registry.tools(Permissions.new(deny_prefixes: ["mcp"]))
    refute Enum.any?(filtered, &String.starts_with?(String.downcase(&1.name), "mcp"))
  end
end
