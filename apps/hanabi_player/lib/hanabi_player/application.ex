defmodule Hanabi.Player.Application do
  @moduledoc """
  The Hanabi.Player application is part of the Hanabi umbrella projects. its purpose is to
  provide a player interface and a TCP connection to the other application - Hanabi.Server.
  """

  use Application

  def start(_type, args) do
    children = [
      {Hanabi.Player, args}
    ]

    opts = [strategy: :one_for_one, name: Hanabi.Player.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
