defmodule Hanabi.Server.Application do
  @moduledoc """
  The hanabi.Server application is is part of the Hanabi umbrella project. The purpose of
  the application is to provide functionality for hosting a server with TCP/IP interface
  for the other application Hanabi.Player to connect.
  """

  use Application

  def start(_type, args) do
    children = [
      {Hanabi.Server, args}
    ]

    opts = [strategy: :one_for_one, name: Hanabi.Server.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
