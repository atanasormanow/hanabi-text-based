defmodule Hanabi.Server do
  @moduledoc """
  Documentation for Hanabi.Server.
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

  @impl true
  def init({ip, port, client_count, game_key}) do
    {:ok, listen_socket} = :gen_tcp.listen(
      port,
      [:binary, packet: 4, active: false, reuseaddr: true, ip: ip]
    )
    clients = accept_clients(client_count, listen_socket, %{}, game_key)
    IO.inspect(clients)
    {:ok, {clients, 0}}
  end

  @impl true
  def handle_cast({:feedback, board}, {clients, on_turn_index}) do
    on_turn_index = rem(on_turn_index, map_size(clients)) + 1
    clients
    |> Map.keys
    |> Enum.each(
      fn i ->
        case i do
          ^on_turn_index ->
            msg = :erlang.term_to_binary({:turn, i, board})
            :ok = :gen_tcp.send(clients[i], msg)
          _other ->
            msg = :erlang.term_to_binary({:info, i, board})
            :ok = :gen_tcp.send(clients[i], msg)
        end
      end
    )
    {:noreply, {clients, on_turn_index + 1}}
  end

  @impl true
  def handle_info({:tcp, sock, packet}, {clients, on_turn_index}) do
    IO.puts("Received a message")
    on_turn_client = clients[on_turn_index]
    case sock do
      ^on_turn_client ->
        process_turn(packet, on_turn_index, sock)
      _other ->
        reject_player(sock, "It wasn't your turn")
    end
    {:noreply, {clients, on_turn_index}}
  end

  @impl true
  def handle_info({:tcp_closed, _sock}, state) do
    IO.puts("A player has disconnected")
    {:noreply, state}
  end

  ###########
  # Private #
  ###########

  defp accept_clients(0, sock, clients, _) do
    GenServer.start_link(Hanabi.Game, map_size(clients))
    :inet.setopts(sock, active: true)
    clients
  end

  defp accept_clients(number_of_clients, sock, clients, game_key) do
    {:ok, new_client} = :gen_tcp.accept(sock)
    case :gen_tcp.recv(new_client, 0) do
      {:ok, auth_msg} ->
        case :erlang.binary_to_term(auth_msg) do
          ^game_key ->
            IO.puts("A player has connected")
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
      _error ->
        accept_clients(number_of_clients, sock, clients, game_key)
    end
  end

  defp process_turn(msg, on_turn_index, sock) do
    case :erlang.binary_to_term(msg) do
      {:color_clue, target_index, color} ->
        IO.puts("clue color")
        GenServer.cast(
          Hanabi.Game,
          {:color_clue, target_index, color}
        )
      {:rank_clue, target_index, rank} ->
        IO.puts("clue rank")
        GenServer.cast(
          Hanabi.Game,
          {:rank_clue, target_index, rank}
        )
      {:play, card_index} ->
        IO.puts("play card")
        GenServer.cast(
          Hanabi.Game,
          {:play, on_turn_index, card_index}
        )
      {:discard, card_index} ->
        IO.puts("discard card")
        GenServer.cast(
          Hanabi.Game,
          {:discard, on_turn_index, card_index}
        )
      _other ->
        reject_player(sock, "Your turn was invalid")
    end
  end

  defp reject_player(sock, reason) do
    GenServer.cast(Hanabi.Game, {:print, "rejecting because of #{reason}"})
    bin = :erlang.term_to_binary({:invalid, reason})
    :gen_tcp.send(sock, bin)
  end
end
