defmodule ClawCode.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: ClawCode.SessionRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ClawCode.SessionSupervisor},
      {Task.Supervisor, name: ClawCode.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClawCode.Supervisor)
  end
end
