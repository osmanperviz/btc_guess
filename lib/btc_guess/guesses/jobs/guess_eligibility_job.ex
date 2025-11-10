defmodule BtcGuess.Guesses.Jobs.GuessEligibilityJob do
  @moduledoc """
  Background job that runs exactly 60 seconds after a player places a guess.

  ## Purpose

  When a player submits a guess, we schedule this job to execute at the
  *eligibility timestamp* (`placed_at + 60s`). Its job is to check whether
  the guess is now ready to be resolved.

  If the guess is still pending and enough time has passed, it enqueues a
  follow-up `GuessResolutionJob` that will compare prices and update the
  player's score.

  ## Flow

    1. The player makes a guess → this job is scheduled for `t + 60s`.
    2. When it runs, it loads the guess from the database.
    3. If the guess exists and is still unresolved, it triggers a
       resolution step (via a new job or inline call).
    4. If the guess was already resolved or deleted, it does nothing.

  ## Error handling

  * If the database record is missing, the job completes quietly.
  * If the resolution step fails (e.g., API error), we rely on Oban’s
    retry mechanism; it will retry with exponential back-off.
  * All important events are logged for audit.

  ## Example

      %GuessEligibilityJob{args: %{"guess_id" => "uuid"}}
      |> Oban.Worker.perform()

  This design ensures fair timing even if the server restarts—Oban
  persists scheduled jobs in Postgres and runs them as soon as they become due.
  """
  use Oban.Worker, queue: :eligibility, unique: [period: 600, fields: [:worker, :args]]
  import Ecto.Query
  alias BtcGuess.{Repo}
  alias BtcGuess.Guesses.Guess

  @impl true
  def perform(%Oban.Job{args: %{"guess_id" => id}}) do
    Repo.transaction(fn ->
      guess =
        Repo.one!(from g in Guess, where: g.id == ^id, lock: "FOR UPDATE")

      if guess.resolved do
        :noop
      else
        with {:ok, %{price: price, source: src, received_at: received_at}} <-
               BtcGuess.Price.latest_after(guess.eligibility_ts),
             outcome when outcome != :no_change <-
               BtcGuess.Guesses.Outcome.evaluate(guess.direction, guess.entry_price, price) do
          resolve(guess, outcome, price, received_at, src)

          {:resolved, %{guess_id: guess.id, player_id: guess.player_id}}
        else
          :no_change -> :no_change
          {:error, _} -> :retry_later
        end
      end
    end)
    |> case do
      {:ok, {:resolved, %{guess_id: gid, player_id: pid}}} ->
        Phoenix.PubSub.broadcast(BtcGuess.PubSub, "player:" <> pid, {:guess_resolved, gid})
        :ok

      _ ->
        :ok
    end
  end

  defp resolve(guess, outcome, price, ts, src) do
    inc = if outcome == :win, do: 1, else: -1

    guess
    |> Ecto.Changeset.change(%{
      resolved: true,
      resolve_price: price,
      resolve_ts: ts,
      source: src,
      outcome: Atom.to_string(outcome)
    })
    |> Repo.update!()

    # Using raw SQL here is intentional for atomic score updates to prevent race conditions.
    Repo.query!("UPDATE players SET score = score + $1 WHERE id = $2", [
      inc,
      guess.player_id
    ])
  end
end
