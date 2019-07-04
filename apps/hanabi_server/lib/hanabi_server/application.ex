defmodule Hanabi.Server.Application do
  @moduledoc false

  use Application

  def start(_type, args) do
    children = [
      {Hanabi.Server, args}
    ]
    opts = [strategy: :one_for_one, name: Hanabi.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end
end