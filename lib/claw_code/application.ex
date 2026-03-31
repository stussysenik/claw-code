defmodule ClawCode.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: ClawCode.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ClawCode.Supervisor)
  end
end
