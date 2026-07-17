defmodule AshTypst.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [AshTypst.ContextPool]
    Supervisor.start_link(children, strategy: :one_for_one, name: AshTypst.Supervisor)
  end
end
