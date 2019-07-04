defmodule Hanabi.Player do
  @moduledoc """
  Documentation for Hanabi.Player.
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

  @impl true
  def init({game_key, ip, port}) do
    case :gen_tcp.connect(ip, port, [:binary, packet: 4, active: false]) do

      {:ok, sock} ->
        :ok = :gen_tcp.send(
          sock,
          :erlang.term_to_binary(game_key)
        )
        {:ok, sock, {:continue, :recv_index}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:recv_index, sock) do
    case :gen_tcp.recv(sock, 0) do

      {:ok, msg} ->
        index = :erlang.term_to_binary(msg)
        :inet.setopts(sock, active: true)
        {:noreply, {sock, index}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:tcp, sock, packet}, {server_sock, index})
  when sock == server_sock do

    IO.puts("Received a message")
    case :erlang.binary_to_term(packet) do

      {:info, i, game_state} ->
        IO.puts("Just info player #{i}")
        parse_info(game_state)

      {:turn, i, game_state} ->
        IO.puts("Your turn player #{i}")
        parse_info(game_state)

      {:invalid, reason} ->
        IO.puts("Invalid turn because: #{reason}")

      {:disconnect, reason} ->
        exit("Connection failed due to #{reason}")

      other ->
        IO.puts("Unexpected message: #{other}")
    end

    {:noreply, {server_sock, index}}
  end

  # TODO handle and reset via Supervisor for :tcp_closed
  @impl true
  def handle_info({:tcp_closed, _sock}, _state) do
    IO.puts("Server has disconnected")

    {:stop, :disconnected, nil}
  end

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
    IO.puts("Sent turn info")

    {:noreply, {sock, player_index}}
  end

  #######
  # API #
  #######

  def clue_color(target, color)
  when is_atom(color) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:color_clue, target, color}}
    )
  end

  def clue_rank(target, rank)
  when is_number(rank) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:rank_clue, target, rank}}
    )
   end

  def play(card_index) do
    GenServer.cast(
      __MODULE__,
      {:turn, {:play, card_index}}
    )
   end

  def discard(card_index) do
    GenServer.cast(
    __MODULE__,
    {:turn, {:discard, card_index}}
  )
  end

  # TODO hardcode some instructions
  def help() do
    "git gud son"
  end

  ###########
  # Private #
  ###########

  # TODO output fancy info with ANSI
  defp parse_info(info) do
    IO.inspect(info)
  end
end
