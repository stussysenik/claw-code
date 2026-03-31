defmodule ClawCode.Manifest do
  alias ClawCode.{Host, NativeRanker, Registry, SessionStore}
  alias ClawCode.Providers.OpenAICompatible

  def render_summary do
    stats = Registry.stats()
    config = OpenAICompatible.resolve_config()
    runtimes = Host.runtime_matrix()

    lines = [
      "# Claw Code Elixir",
      "",
      "Version: #{ClawCode.version()}",
      "Commands mirrored: #{stats.commands}",
      "Tools mirrored: #{stats.tools}",
      "Zig ranker available: #{NativeRanker.available?()}",
      "Provider configured: #{OpenAICompatible.configured?(config)}",
      "Default provider: #{config.provider}",
      "Session directory: #{SessionStore.root_dir()}",
      "",
      "Runtime matrix:",
      Enum.map_join(runtimes, "\n", fn runtime ->
        "- #{runtime.label}: #{if runtime.available, do: runtime.engine, else: "missing"}"
      end)
    ]

    Enum.join(lines, "\n")
  end

  def render_manifest do
    stats = Registry.stats()

    [
      "# Manifest",
      "",
      "- commands: #{stats.commands}",
      "- tools: #{stats.tools}",
      "- local tools: #{Enum.join(ClawCode.Tools.Builtin.maybe_enabled_names(), ", ")}"
    ]
    |> Enum.join("\n")
  end

  def render_doctor do
    config = OpenAICompatible.resolve_config()
    facts = Host.kernel_facts()

    [
      "# Doctor",
      "",
      "- elixir: #{facts.elixir}",
      "- otp: #{facts.otp}",
      "- uname: #{facts.uname}",
      "- shell: #{facts.shell}",
      "- zig: #{exec("zig")}",
      "- python3: #{runtime_engine(:python)}",
      "- lua: #{runtime_engine(:lua)}",
      "- common_lisp: #{runtime_engine(:common_lisp)}",
      "- provider: #{config.provider}",
      "- base_url: #{config.base_url || "missing"}",
      "- api_key: #{mask(config.api_key)}",
      "- model: #{config.model || "missing"}"
    ]
    |> Enum.join("\n")
  end

  defp exec(name) do
    System.find_executable(name) || "missing"
  end

  defp runtime_engine(id) do
    case Host.runtime(id) do
      %{available: true, engine: engine} -> engine
      _ -> "missing"
    end
  end

  defp mask(nil), do: "missing"
  defp mask(value) when byte_size(value) <= 6, do: String.duplicate("*", byte_size(value))

  defp mask(value),
    do:
      String.slice(value, 0, 3) <>
        String.duplicate("*", byte_size(value) - 6) <> String.slice(value, -3, 3)
end
