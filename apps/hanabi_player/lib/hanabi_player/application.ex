defmodule Hanabi.Player.Application do
  @moduledoc false

  use Application

  def start(_type, args) do
    children = [
      {Hanabi.Player, args}
    ]
    opts = [strategy: :one_for_one, name: Hanabi.Player.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
