defmodule ClawCode.Application do
  use Application
  alias ClawCode.EnvLoader

  @impl true
  def start(_type, _args) do
    if System.get_env("MIX_ENV") != "test" do
      :ok = EnvLoader.load()
    end

    children = [
      {Registry, keys: :unique, name: ClawCode.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ClawCode.SessionSupervisor},
      {Task.Supervisor, name: ClawCode.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClawCode.Supervisor)
  end
end
