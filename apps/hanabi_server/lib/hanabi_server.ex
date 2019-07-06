defmodule Hanabi.Server do
  @moduledoc """
  The Server module of the Hanabi's server application.

  This module is the middleman for the players and the game logic. It has a GenServer
  behaveiour and represents a TCP based server.

  The used interface for TCP/IP is Erlang's :gen_tcp module. All the messages are elixir
  structures, sent/received as serialized/deserialized binaries.

  By default the server is hosted on port 4444 at 127.0.0.1(localhost). The options are set
  as :mod in mix.exs.
  """

  use GenServer

  def start_link({client_count, game_key})
      when client_count < 7 and client_count > 1 do
    ip = Application.get_env(:hanabi, :ip, {127, 0, 0, 1})
    port = Application.get_env(:hanabi, :port, 4444)
    IO.inspect(ip)

    GenServer.start_link(
      __MODULE__,
      {ip, port, client_count, game_key},
      name: __MODULE__
    )
  end

  #############
  # Callbacks #
  #############

  @doc """
  Given an ip, port, a number of clients and a game key - accepts the given number of
  players via accept_clients/4.

  The initial state is {clients, 0}. clients is a map with keys - player indexes
  (starting from 1), and values - the client sockets.

  The TCP connection is initially set to {:active, false}
  """
  @impl true
  def init({ip, port, client_count, game_key}) do
    {:ok, listen_socket} =
      :gen_tcp.listen(
        port,
        [:binary, packet: 4, active: false, reuseaddr: true, ip: ip]
      )

    clients = accept_clients(client_count, listen_socket, %{}, game_key)
    IO.inspect(clients)

    {:ok, {clients, 0}}
  end

  @doc "Send the game state to the players, including which player is on turn "
  @impl true
  def handle_cast({:send_feedback, board}, {clients, on_turn_index}) do
    on_turn_index = rem(on_turn_index, map_size(clients)) + 1

    clients
    |> Map.keys()
    |> Enum.each(fn i ->
      case i do
        ^on_turn_index ->
          msg = :erlang.term_to_binary({:turn, board})
          :ok = :gen_tcp.send(clients[i], msg)

        _other ->
          msg = :erlang.term_to_binary({:info, board})
          :ok = :gen_tcp.send(clients[i], msg)
      end
    end)

    {:noreply, {clients, on_turn_index}}
  end

  @doc """
  Processes the turn data received from a player. Send a message back via reject_player/2
  if the received data was somehow invalid. On receiving a valid data forward the data to
  the Hanabi.Game module via GenServer.cast/2.
  """
  @impl true
  def handle_info({:tcp, sock, packet}, {clients, on_turn_index}) do
    IO.puts("Received a message from player #{on_turn_index}")
    on_turn_client = clients[on_turn_index]

    case sock do
      ^on_turn_client ->
        case :erlang.binary_to_term(packet) do
          {:color_clue, ^on_turn_index, _} ->
            reject_player(sock, "You cannot clue yourself")

          {:rank_clue, ^on_turn_index, _} ->
            reject_player(sock, "You cannot clue yourself")

          {turn_id, player_index, action_info} ->
            GenServer.cast(
              Hanabi.Game,
              {turn_id, player_index, action_info}
            )

          _other ->
            reject_player(sock, "Your turn was invalid")
        end

      _other ->
        reject_player(sock, "It wasn't your turn")
    end

    {:noreply, {clients, on_turn_index}}
  end

  # TODO handle reconnect
  @doc "Prompt if a player has disconnected."
  @impl true
  def handle_info({:tcp_closed, _sock}, state) do
    IO.puts("A player has disconnected")
    {:noreply, state}
  end

  ###########
  # Private #
  ###########

  defp accept_clients(0, sock, clients, _) do
    :inet.setopts(sock, active: true)

    clients
    |> Map.values()
    |> Enum.each(fn s ->
      :inet.setopts(s, active: true)
    end)

    GenServer.start_link(Hanabi.Game, map_size(clients), name: Hanabi.Game)

    clients
  end

  defp accept_clients(number_of_clients, sock, clients, game_key) do
    {:ok, new_client} = :gen_tcp.accept(sock)

    case :gen_tcp.recv(new_client, 0) do
      {:ok, auth_msg} ->
        case :erlang.binary_to_term(auth_msg) do
          ^game_key ->
            player_index_bin = :erlang.term_to_binary(number_of_clients)

            :gen_tcp.send(new_client, player_index_bin)
            IO.puts("A Player has connected")

            accept_clients(
              number_of_clients - 1,
              sock,
              Map.put(clients, number_of_clients, new_client),
              game_key
            )

          _other ->
            disconnect_msg =
              :erlang.term_to_binary(
                {:disconnect, "Wrong authentication key!"}
              )

            :gen_tcp.send(new_client, disconnect_msg)
            :gen_tcp.close(new_client)

            accept_clients(number_of_clients, sock, clients, game_key)
        end

      {:error, reason} ->
        IO.puts("An error has occured due to #{reason}")
        accept_clients(number_of_clients, sock, clients, game_key)
    end
  end

  defp reject_player(sock, reason) do
    bin = :erlang.term_to_binary({:invalid, reason})
    :gen_tcp.send(sock, bin)
  end
end
