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
  alias BtcGuess.Guesses.Outcome
  alias BtcGuess.Guesses.Jobs.ResolveGuessJob
  alias BtcGuess.Players.Player

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"guess_id" => id}}) do
    require Logger
    Logger.info("GuessEligibilityJob starting for guess #{id}")

    result =
      Repo.transaction(fn ->
        # Lock the guess row once
        guess =
          Repo.one!(from g in Guess, where: g.id == ^id, lock: "FOR UPDATE")

        Logger.info(
          "Guess loaded: resolved=#{guess.resolved}, eligibility_ts=#{guess.eligibility_ts}, now=#{DateTime.utc_now()}"
        )

        cond do
          guess.resolved ->
            Logger.info("Guess already resolved, skipping")
            {:noop, nil}

          DateTime.diff(guess.eligibility_ts, DateTime.utc_now()) > 1 ->
            # Fired early? reschedule for the exact eligibility moment
            Logger.info("Job fired too early, rescheduling for #{guess.eligibility_ts}")
            Oban.insert!(new(%{"guess_id" => id}, scheduled_at: guess.eligibility_ts))
            {:noop, nil}

          true ->
            Logger.info("Attempting to resolve guess...")

            case BtcGuess.Price.latest_after(guess.eligibility_ts) do
              {:ok, %{price: price, source: source, received_at: received_at}} ->
                Logger.info("Got price: #{price}, evaluating outcome...")

                case Outcome.evaluate(guess.direction, guess.entry_price, price) do
                  :no_change ->
                    Logger.info("Price unchanged, scheduling ResolveGuessJob")
                    # Hand over to the retrying resolver job
                    Oban.insert!(
                      ResolveGuessJob.new(%{"guess_id" => id},
                        scheduled_at: DateTime.add(DateTime.utc_now(), 2, :second)
                      )
                    )

                    {:noop, nil}

                  out ->
                    Logger.info("Outcome: #{out}, resolving guess...")
                    inc = if out == :win, do: 1, else: -1

                    guess
                    |> Ecto.Changeset.change(%{
                      resolved: true,
                      resolve_price: price,
                      resolve_ts: received_at,
                      source: source,
                      outcome: out
                    })
                    |> Repo.update!()

                    from(p in Player, where: p.id == ^guess.player_id)
                    |> Repo.update_all(inc: [score: inc])

                    {:resolved, %{player_id: guess.player_id, guess_id: guess.id}}
                end

              {:error, reason} ->
                Logger.error(
                  "Failed to get price: #{inspect(reason)}, scheduling ResolveGuessJob"
                )

                Oban.insert!(
                  ResolveGuessJob.new(%{"guess_id" => id},
                    scheduled_at: DateTime.add(DateTime.utc_now(), 2, :second)
                  )
                )

                {:noop, nil}
            end
        end
      end)

    case result do
      {:ok, {:resolved, %{player_id: pid, guess_id: gid}}} ->
        topic = "player:" <> pid
        Logger.info("Broadcasting guess_resolved for guess #{gid} to topic: #{topic}")

        Phoenix.PubSub.broadcast(BtcGuess.PubSub, topic, {:guess_resolved, gid})
        :ok

      _ ->
        :ok
    end
  end
end
