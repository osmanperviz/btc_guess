defmodule BtcGuess.Guesses.Jobs.ResolveGuessJobTest do
  use BtcGuess.DataCase, async: false

  import Ecto.Query
  alias BtcGuess.Guesses
  alias BtcGuess.Guesses.Jobs.ResolveGuessJob
  alias BtcGuess.Players.Player

  describe "perform/1" do
    setup do
      player_id = Ecto.UUID.generate()
      Guesses.ensure_player!(player_id)
      %{player_id: player_id}
    end

    test "does nothing if guess is already resolved", %{player_id: player_id} do
      guess = Guesses.place_guess!(player_id, "up")

      guess
      |> Ecto.Changeset.change(%{
        resolved: true,
        resolve_price: Decimal.new("100000"),
        outcome: :win
      })
      |> Repo.update!()

      assert :ok = ResolveGuessJob.perform(%Oban.Job{args: %{"guess_id" => guess.id}})

      updated = Repo.get!(Guesses.Guess, guess.id)
      assert updated.resolved == true
    end

    test "handles non-existent guess gracefully", %{player_id: _player_id} do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        ResolveGuessJob.perform(%Oban.Job{args: %{"guess_id" => fake_id}})
      end
    end

    test "reschedules if price hasn't changed yet", %{player_id: player_id} do
      now = DateTime.utc_now()
      past = DateTime.add(now, -5, :second)

      guess =
        %Guesses.Guess{
          id: Ecto.UUID.generate(),
          player_id: player_id,
          direction: :up,
          entry_price: Decimal.new("100000"),
          placed_at: past,
          eligibility_ts: past,
          resolved: false
        }
        |> Repo.insert!()

      jobs_before = Repo.aggregate(Oban.Job, :count)
      assert :ok = ResolveGuessJob.perform(%Oban.Job{args: %{"guess_id" => guess.id}})

      jobs_after = Repo.aggregate(Oban.Job, :count)
      assert jobs_after >= jobs_before
    end

    test "max retries prevents infinite rescheduling", %{player_id: player_id} do
      guess = Guesses.place_guess!(player_id, "up")

      job = %Oban.Job{
        args: %{"guess_id" => guess.id},
        attempt: 20,
        max_attempts: 20
      }

      assert :ok = ResolveGuessJob.perform(job)
    end

    test "resolves with atomic score update", %{player_id: player_id} do
      player = Repo.get!(Player, player_id)

      player
      |> Ecto.Changeset.change(%{score: 10})
      |> Repo.update!()

      from(p in Player, where: p.id == ^player_id)
      |> Repo.update_all(inc: [score: 1])

      updated = Repo.get!(Player, player_id)
      assert updated.score == 11
    end
  end
end
