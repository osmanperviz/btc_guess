defmodule BtcGuess.Guesses.Jobs.GuessEligibilityJobTest do
  use BtcGuess.DataCase, async: false

  alias BtcGuess.Guesses
  alias BtcGuess.Guesses.Jobs.GuessEligibilityJob
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

      assert :ok = GuessEligibilityJob.perform(%Oban.Job{args: %{"guess_id" => guess.id}})

      updated = Repo.get!(Guesses.Guess, guess.id)
      assert updated.resolved == true
    end

    test "reschedules if run too early", %{player_id: player_id} do
      now = DateTime.utc_now()
      future = DateTime.add(now, 10, :second)

      guess =
        %Guesses.Guess{
          id: Ecto.UUID.generate(),
          player_id: player_id,
          direction: :up,
          entry_price: Decimal.new("100000"),
          placed_at: now,
          eligibility_ts: future,
          resolved: false
        }
        |> Repo.insert!()

      jobs_before = Repo.aggregate(Oban.Job, :count)

      assert :ok = GuessEligibilityJob.perform(%Oban.Job{args: %{"guess_id" => guess.id}})

      updated = Repo.get!(Guesses.Guess, guess.id)
      assert updated.resolved == false

      jobs_after = Repo.aggregate(Oban.Job, :count)
      assert jobs_after == jobs_before + 1

      new_job =
        Repo.one(
          from j in Oban.Job,
            where: j.args["guess_id"] == ^guess.id,
            order_by: [desc: j.id],
            limit: 1
        )

      assert new_job != nil
      assert new_job.state == "scheduled"
    end

    test "handles non-existent guess gracefully", %{player_id: _player_id} do
      fake_id = Ecto.UUID.generate()

      # Should raise because guess doesn't exist
      assert_raise Ecto.NoResultsError, fn ->
        GuessEligibilityJob.perform(%Oban.Job{args: %{"guess_id" => fake_id}})
      end
    end

    test "decrements score on loss", %{player_id: player_id} do
      player = Repo.get!(Player, player_id)

      player
      |> Ecto.Changeset.change(%{score: 5})
      |> Repo.update!()

      from(p in Player, where: p.id == ^player_id)
      |> Repo.update_all(inc: [score: -1])

      updated = Repo.get!(Player, player_id)
      assert updated.score == 4
    end

    test "increments score on win", %{player_id: player_id} do
      player = Repo.get!(Player, player_id)
      initial_score = player.score

      from(p in Player, where: p.id == ^player_id)
      |> Repo.update_all(inc: [score: 1])

      updated = Repo.get!(Player, player_id)
      assert updated.score == initial_score + 1
    end

    test "atomic score update prevents race conditions", %{player_id: player_id} do
      player = Repo.get!(Player, player_id)
      initial_score = player.score

      parent = self()
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, parent})

      # Simulate 10 concurrent score updates

      # This runs CONCURRENTLY (all at once)
      # update_1 ─┐
      # update_2 ─┤
      # update_3 ─┼─> All happening simultaneously
      # ...      ─┤
      # update_10─┘
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            from(p in Player, where: p.id == ^player_id)
            |> Repo.update_all(inc: [score: 1])
          end)
        end

      Enum.each(tasks, &Task.await/1)

      updated = Repo.get!(Player, player_id)
      assert updated.score == initial_score + 10
    end
  end
end
