defmodule Hanabi.Player do
  @moduledoc """
  The Player module of the Hanabi player application.

  This module uses the :gen_tcp to connect and communicate with the Hanabi.Server module.

  It provides a basic interface for the actions players can perform during their turn.

  The player has a GenServer behaveiour and its state is a tuple of two elements. The first
  being the server's socket and the second - the player's index (in turn order).

  By default the players initialize connection on port 4444 at 127.0.0.1 (localhost).
  The options are set as :mod in mix.exs.
  """

  use GenServer

  def start_link({game_key, ip, port}) do
    GenServer.start_link(
      __MODULE__,
      {game_key, ip, port},
      name: __MODULE__
    )
  end

  #############
  # Callbacks #
  #############

  @doc """
  The connection to the server is established with the needed password(game key). The socket
  of the connection is passed down with a continue instruction. The socket starts off with
  {:active, false}
  """
  @impl true
  def init({game_key, ip, port}) do
    case :gen_tcp.connect(ip, port, [:binary, packet: 4, active: false]) do
      {:ok, sock} ->
        :ok =
          :gen_tcp.send(
            sock,
            :erlang.term_to_binary(game_key)
          )

        {:ok, sock, {:continue, :recv_index}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @doc """
  The player's index is received from the server and passed down as part of the state.
  The option :active is set to true.
  """
  @impl true
  def handle_continue(:recv_index, sock) do
    case :gen_tcp.recv(sock, 0) do
      {:ok, msg} ->
        index = :erlang.binary_to_term(msg)
        IO.puts(index)
        :inet.setopts(sock, active: true)
        {:noreply, {sock, index}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # TODO handle and revive for {:stop, reason}
  @doc "Receive data from the server. And display it if its a valid game state"
  @impl true
  def handle_info({:tcp, sock, packet}, {server_sock, index})
      when sock == server_sock do
    case :erlang.binary_to_term(packet) do
      {:info, game_state} ->
        IO.puts("Just info player #{index}")
        parse_info(game_state, index)

      {:turn, game_state} ->
        IO.puts("Your turn player #{index}")
        parse_info(game_state, index)

      {:invalid, reason} ->
        IO.puts("Invalid turn because: #{reason}")

      {:disconnect, reason} ->
        {:stop, reason}

      other ->
        IO.puts("Unexpected message: #{other}")
    end

    {:noreply, {server_sock, index}}
  end

  @doc "Prompt and stop if the server disconnects."
  @impl true
  def handle_info({:tcp_closed, _sock}, _state) do
    IO.puts("Server has disconnected")

    {:stop, :disconnected, nil}
  end

  @doc """
  Send the player's turn data to the server. Include the player's index if its a play or
  a discard action.
  """
  @impl true
  def handle_cast({:turn, msg}, {sock, player_index}) do
    msg_from =
      case msg do
        {:play, card_index} ->
          {:play, player_index, card_index}

        {:discard, card_index} ->
          {:discard, player_index, card_index}

        other ->
          other
      end

    msg_bin = :erlang.term_to_binary(msg_from)
    :gen_tcp.send(sock, msg_bin)

    {:noreply, {sock, player_index}}
  end

  #######
  # API #
  #######

  @doc """
  Basic functions, representing the actions players can perform on their turn. All of them
  except help/0 do a GenServer.cast/2.
  """
  # NOTE calling them should be more user friendly as a command line application

  def clue(target, color)
      when is_atom(color) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:color_clue, target, color}}
    )
  end

  def clue(target, rank)
      when is_number(rank) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:rank_clue, target, rank}}
    )
  end

  def clue(_target, _clue) do
    IO.puts("Invalid clue")
  end

  def play(card_index) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:play, card_index - 1}}
    )
  end

  def discard(card_index) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:discard, card_index - 1}}
    )
  end

  # TODO hardcode some instructions
  def help do
    "git gud son"
  end

  ###########
  # Private #
  ###########

  # NOTE player hands should be filtered
  #      in the server
  # TODO output fancy info with ANSI
  defp parse_info(info, index) do
    IO.inspect(%{info | hands: %{info.hands | index => elem(info.hands[index], 1)}})
  end
end
