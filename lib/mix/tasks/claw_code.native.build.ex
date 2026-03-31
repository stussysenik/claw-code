defmodule Mix.Tasks.ClawCode.Native.Build do
  use Mix.Task

  @shortdoc "Build the Zig token ranker for claw_code"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    path = ClawCode.NativeRanker.build()
    Mix.shell().info("native ranker ready at #{path}")
  end
end
