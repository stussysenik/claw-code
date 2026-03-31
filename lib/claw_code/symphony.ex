defmodule ClawCode.Symphony do
  alias ClawCode.{Host, Manifest, Providers.OpenAICompatible, Registry, Router, Tools.Builtin}

  def run(prompt, opts \\ []) do
    agents = [
      {:manifest, fn -> Manifest.render_manifest() end},
      {:doctor, fn -> Manifest.render_doctor() end},
      {:routing, fn -> Router.route(prompt, opts) end},
      {:local_tools, fn -> Builtin.maybe_enabled_names(opts) end},
      {:provider, fn -> OpenAICompatible.resolve_config(opts) end},
      {:host, fn -> %{facts: Host.kernel_facts(), runtimes: Host.runtime_matrix()} end},
      {:registry, fn -> Registry.stats() end}
    ]

    results =
      Task.Supervisor.async_stream_nolink(
        ClawCode.TaskSupervisor,
        agents,
        fn {name, fun} -> {name, fun.()} end,
        ordered: false,
        timeout: 30_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:failed, reason}
      end)
      |> Enum.into(%{})

    %{prompt: prompt, agents: results}
  end

  def render(report) do
    host = report.agents.host
    provider = report.agents.provider

    [
      "# Symphony",
      "",
      "Prompt: #{report.prompt}",
      "",
      "## Registry",
      "- commands: #{report.agents.registry.commands}",
      "- tools: #{report.agents.registry.tools}",
      "",
      "## Host",
      "- uname: #{host.facts.uname}",
      "- shell: #{host.facts.shell}",
      "- cwd: #{host.facts.cwd}",
      "",
      "## Runtimes",
      Enum.map_join(host.runtimes, "\n", fn runtime ->
        "- #{runtime.label}: #{if runtime.available, do: runtime.engine, else: "missing"}"
      end),
      "",
      "## Provider",
      "- provider: #{provider.provider}",
      "- configured: #{OpenAICompatible.configured?(provider)}",
      "- base_url: #{provider.base_url || "missing"}",
      "- model: #{provider.model || "missing"}",
      "",
      "## Local Tools",
      Enum.map_join(report.agents.local_tools, "\n", &"- #{&1}"),
      "",
      "## Routing",
      render_matches(report.agents.routing),
      "",
      "## Manifest",
      report.agents.manifest
    ]
    |> Enum.join("\n")
  end

  defp render_matches([]), do: "- none"

  defp render_matches(matches) do
    Enum.map_join(matches, "\n", fn match ->
      "- [#{match.kind}] #{match.name} (#{match.score}) - #{match.source_hint}"
    end)
  end
end
