defmodule Hanabi.PlayerTest do
  use ExUnit.Case
  doctest Hanabi.Player

  test "greets the world" do
    assert Hanabi.Player.hello() == :world
  end
end
