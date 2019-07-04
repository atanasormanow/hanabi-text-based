defmodule Hanabi.Game do
  @moduledoc """
  Documentation for Hanabi.Game
  """

  @type hint :: 0..8
  @type bomb :: 0..3
  @type rank :: 0..5
  @type colr :: :red | :green | :blue | :white | :yellow
  @type card :: {rank, colr}
  @type info :: {rank | nil, colr | nil}
  @type hand :: {[card], [info]}
  @type play :: %{required(colr) => rank}

  @type state :: %{
    play: play,
    discard: [card],
    deck: [card],
    hands: [hand],
    hints: hint,
    bombs: bomb
  }

  @default_colors [:r,:g,:b,:w,:y]
  @default_ranks [1,1,1,2,2,3,3,4,4,5]

  use GenServer

  def start_link(player_count) do
    GenServer.start_link(
      __MODULE__,
      player_count,
      name: __MODULE__
    )
  end

  @impl true
  def init(player_count) do
    state = init_state(player_count)
    IO.inspect(state.hands)

    {:ok, state, {:continue, :feedback}}
  end

  #############
  # Callbacks #
  #############

  @impl true
  def handle_cast({:color_clue, target, color}, state) do
    IO.puts("player #{target} was clued a #{color}")
    {
      :noreply,
      %{state | hands:
        Map.update!(
          state.hands,
          target,
          fn hand ->
            clue_hand(hand, color, :color_clue)
          end
        )
      },
      {:continue, :feedback}
    }
  end

  @impl true
  def handle_cast({:rank_clue, target, rank}, state) do
    IO.puts("player #{target} was clued a #{rank}")
    {
      :noreply,
      %{state | hands:
        Map.update!(
         state.hands,
         target,
         fn hand ->
           clue_hand(hand, rank, :rank_clue)
         end
        )
      },
      {:continue, :feedback}
    }
  end

  @impl true
  def handle_cast({:play, player_index, card_index}, state) do
    IO.puts("player #{player_index} played a card")
    {rank, color} =
      state.hands[player_index]
      |> Enum.at(card_index)

    desired_rank = rank - 1

    {play_new, discard_new, deck_new, hand_new} =
      case state.play[color] do

        ^desired_rank ->
          play_card(
            state.play,
            state.discard,
            state.deck,
            state.hands[player_index],
            card_index
          )

        _other ->
          discard_card(
            state.play,
            state.discard,
            state.deck,
            state.hands[player_index],
            card_index
          )
      end

    {
      :noreply,
      %{
        state |
        play: play_new,
        discard: discard_new,
        deck: deck_new,
        hands: %{state.hands | player_index => hand_new}
      }, {:continue, :feedback}
    }
  end

  @impl true
  def handle_cast({:discard, player_index, card_index}, state) do
    IO.puts("player #{player_index} discarded a card")
    {_, discard_new, deck_new, hand_new} =
      discard_card(
        state.play,
        state.discard,
        state.deck,
        state.hands[player_index],
        card_index
      )

    {
      :noreply,
      %{
        state |
        discard: discard_new,
        deck: deck_new,
        hands: %{state.hands | player_index => hand_new},
        hints: state.hints + 1
      },
      {:continue, :feedback}
    }
  end

  @impl true
  def handle_continue(:feedback, state) do
    IO.puts("Sending feedback!")
    deck_size = Enum.count(state.deck)
    GenServer.cast(Hanabi.Server, {:send_feedback, %{state | deck: deck_size}})

    {:noreply, state}
  end

  ###########
  # Private #
  ###########

  @spec init_state(number) :: state
  defp init_state(player_count) do
    deck = create_deck(@default_colors, @default_ranks)
    {hands, deck} = deal(deck, player_count)

    hands =
      Enum.zip(1..6, hands)
      |> Map.new

    initial_play =
      Enum.zip(@default_colors, List.duplicate(0, 5))
      |> Map.new

    %{
      play: initial_play,
      discard: [],
      deck: deck,
      hands: hands,
      hints: 8,
      bombs: 0
    }
  end

  @spec create_deck([colr], [rank]) :: [card]
  defp create_deck(colors, ranks) do
    Enum.flat_map(ranks, fn r -> create_suite(colors, r) end)
    |> Enum.shuffle
  end

  @spec create_suite([colr], rank) :: [card]
  defp create_suite(colors, rank) do
    List.duplicate(rank, Enum.count(colors))
    |> Enum.zip(colors)
  end

  @spec deal([card], number) :: {[hand], [card]}
  defp deal(deck, player_count) do
    cards_per_hand = cards_per_player(player_count)
    init_info = List.duplicate({nil, nil}, cards_per_hand)
    {dealt, deck} = Enum.split(deck, player_count * cards_per_hand)

    dealt =
      Enum.chunk_every(dealt, cards_per_hand, cards_per_hand)
      |> Enum.map(fn h -> {h, init_info} end)

    {dealt, deck}
  end

  @spec cards_per_player(number) :: number
  defp cards_per_player(player_count) do
   case player_count do
      2 -> 5
      3 -> 5
      4 -> 4
      5 -> 4
      6 -> 3
    end
  end

  @spec clue_hand(hand, colr, atom) :: hand
  defp clue_hand({cards, info}, color_clue, :color_clue) do
    Enum.zip({cards, info})
    |> Enum.map(
      fn {{rank, color}, {rank_info, _color_info}} ->
        case color do
          ^color_clue -> {{rank, color}, {rank_info, color}}
          other -> other
        end
      end
    )
    |> Enum.unzip
  end

  @spec clue_hand(hand, rank, atom) :: hand
  defp clue_hand({cards, info}, rank_clue, :rank_clue) do
    Enum.zip(cards, info)
    |> Enum.map(
      fn {{rank, color}, {_rank_info, color_info}} ->
        case rank do
          ^rank_clue -> {{rank, color}, {rank, color_info}}
          other -> other
        end
      end
    )
    |> Enum.unzip
  end

  @spec draw_card(hand, [card]) :: {hand, [card]}
  defp draw_card({cards, info}, deck) do
    [top_card | deck_rest] = deck

    {
      {
        [top_card | cards],
        [{nil, nil} | info]
      },
      deck_rest
    }
  end

  @spec discard_card(play, [card], [card], hand, number)
  :: {play, [card], [card], hand}
  defp play_card(play, discard, deck, hand, card_index) do
    {rank, color} =
      elem(hand, 0)
      |> Enum.at(card_index)

    {hand_new, deck_new} = draw_card(deck, hand)

    {
      %{play | color => rank},
      discard,
      deck_new,
      hand_new
    }
  end

  @spec discard_card(play, [card], [card], hand, number)
  :: {play , [card], [card], hand}
  defp discard_card(play, discard, deck, hand, card_index) do
    discard_card =
      elem(hand, 0)
      |> Enum.at(card_index)

    {hand_new, deck_new} =
      {
        elem(hand, 1) |> List.delete_at(card_index),
        elem(hand, 0) |> List.delete_at(card_index)
      }
      |> draw_card(deck)

    {
      play,
      [discard_card | discard],
      deck_new,
      hand_new,
    }
  end
end
