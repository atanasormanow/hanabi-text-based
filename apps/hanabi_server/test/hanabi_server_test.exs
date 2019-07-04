defmodule Hanabi.ServerTest do
  use ExUnit.Case
  doctest Hanabi.Server

  test "greets the world" do
    assert Hanabi.Server.hello() == :world
  end
end
