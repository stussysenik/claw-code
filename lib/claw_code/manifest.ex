defmodule ClawCode.Manifest do
  alias ClawCode.{Host, NativeRanker, Registry, Runtime, SessionStore}
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

  def render_doctor(opts \\ []) do
    payload = doctor_payload(opts)

    [
      "# Doctor",
      "",
      "- elixir: #{payload.elixir}",
      "- otp: #{payload.otp}",
      "- uname: #{payload.uname}",
      "- shell: #{payload.shell}",
      "- zig: #{payload.zig}",
      "- python3: #{payload.python3}",
      "- lua: #{payload.lua}",
      "- common_lisp: #{payload.common_lisp}",
      "- provider: #{payload.provider}",
      "- configured: #{payload.configured}",
      "- tool_policy: #{payload.tool_policy}",
      "- request_url: #{payload.request_url || "missing"}",
      "- base_url: #{payload.base_url.value || "missing"} (#{payload.base_url.source})",
      "- api_key: #{payload.api_key.masked} (#{payload.api_key.source})",
      "- model: #{payload.model.value || "missing"} (#{payload.model.source})",
      "- missing: #{render_missing_fields(payload.missing)}"
    ]
    |> Enum.join("\n")
  end

  def doctor_payload(opts \\ []) do
    config = OpenAICompatible.resolve_config(opts)
    diagnostics = OpenAICompatible.diagnostics(opts)
    facts = Host.kernel_facts()

    %{
      elixir: facts.elixir,
      otp: to_string(facts.otp),
      uname: facts.uname,
      shell: facts.shell,
      zig: exec("zig"),
      python3: runtime_engine(:python),
      lua: runtime_engine(:lua),
      common_lisp: runtime_engine(:common_lisp),
      provider: config.provider,
      configured: diagnostics.configured,
      tool_policy: Runtime.tool_policy(opts),
      request_url: diagnostics.request_url,
      base_url: %{
        value: config.base_url,
        source: diagnostics.fields.base_url.source
      },
      api_key: %{
        masked: mask(config.api_key),
        source: diagnostics.fields.api_key.source
      },
      model: %{
        value: config.model,
        source: diagnostics.fields.model.source
      },
      missing: diagnostics.missing_fields
    }
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

  defp render_missing_fields([]), do: "none"
  defp render_missing_fields(fields), do: Enum.map_join(fields, ", ", &to_string/1)

  defp mask(nil), do: "missing"
  defp mask(value) when byte_size(value) <= 6, do: String.duplicate("*", byte_size(value))

  defp mask(value),
    do:
      String.slice(value, 0, 3) <>
        String.duplicate("*", byte_size(value) - 6) <> String.slice(value, -3, 3)
end
