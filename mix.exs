defmodule ClawCode.MixProject do
  use Mix.Project

  def project do
    [
      app: :claw_code,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: ClawCode.CLI],
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :inets],
      mod: {ClawCode.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      check: ["format --check-formatted", "test"]
    ]
  end
end
