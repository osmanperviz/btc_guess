defmodule BtcGuess.GuessesTest do
  use BtcGuess.DataCase, async: true

  alias BtcGuess.Guesses
  alias BtcGuess.Guesses.Guess
  alias BtcGuess.Players.Player

  describe "place_guess!/2" do
    setup do
      player_id = Ecto.UUID.generate()
      Guesses.ensure_player!(player_id)
      %{player_id: player_id}
    end

    test "creates a guess with correct attributes", %{player_id: player_id} do
      guess = Guesses.place_guess!(player_id, "up")

      assert guess.player_id == player_id
      assert guess.direction == :up
      assert guess.resolved == false
      assert guess.entry_price != nil
      assert guess.eligibility_ts != nil
      # Eligibility should be ~60 seconds from now
      diff = DateTime.diff(guess.eligibility_ts, guess.placed_at)
      assert diff >= 59 and diff <= 61
    end

    test "prevents multiple open guesses for same player", %{player_id: player_id} do
      Guesses.place_guess!(player_id, "up")

      assert_raise Ecto.ConstraintError, fn ->
        Guesses.place_guess!(player_id, "down")
      end
    end

    test "allows new guess after previous is resolved", %{player_id: player_id} do
      guess1 = Guesses.place_guess!(player_id, "up")

      guess1
      |> Ecto.Changeset.change(%{
        resolved: true,
        resolve_price: Decimal.new("100000"),
        resolve_ts: DateTime.utc_now(),
        outcome: :win
      })
      |> Repo.update!()

      guess2 = Guesses.place_guess!(player_id, "down")
      assert guess2.id != guess1.id
    end
  end

  describe "open_guess_for/1" do
    test "returns nil when no open guess exists" do
      player_id = Ecto.UUID.generate()
      Guesses.ensure_player!(player_id)

      assert Guesses.open_guess_for(player_id) == nil
    end

    test "returns the open guess when it exists" do
      player_id = Ecto.UUID.generate()
      Guesses.ensure_player!(player_id)
      guess = Guesses.place_guess!(player_id, "up")

      open = Guesses.open_guess_for(player_id)
      assert open.id == guess.id
    end

    test "returns nil when guess is resolved" do
      player_id = Ecto.UUID.generate()
      Guesses.ensure_player!(player_id)
      guess = Guesses.place_guess!(player_id, "up")

      guess
      |> Ecto.Changeset.change(%{resolved: true, outcome: :win})
      |> Repo.update!()

      assert Guesses.open_guess_for(player_id) == nil
    end
  end

  describe "ensure_player!/1" do
    test "creates a new player if doesn't exist" do
      player_id = Ecto.UUID.generate()
      player = Guesses.ensure_player!(player_id)

      assert player.id == player_id
      assert player.score == 0
    end

    test "returns existing player without creating duplicate" do
      player_id = Ecto.UUID.generate()
      player1 = Guesses.ensure_player!(player_id)
      player2 = Guesses.ensure_player!(player_id)

      assert player1.id == player2.id
      assert Repo.aggregate(Player, :count) == 1
    end
  end
end
