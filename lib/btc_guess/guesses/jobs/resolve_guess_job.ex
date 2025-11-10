defmodule BtcGuess.Guesses.Jobs.ResolveGuessJob do
  use Oban.Worker, queue: :resolution, unique: [period: 600, fields: [:worker, :args]]

  import Ecto.Query
  alias BtcGuess.{Repo}
  alias BtcGuess.Guesses.Guess
  alias BtcGuess.Guesses.Outcome

  @backoff_seconds 2
  # stop after ~10 minutes if market is weirdly flat
  @cap_seconds 600

  @impl true
  def perform(%Oban.Job{args: %{"guess_id" => id}, attempt: attempt}) do
    result =
      Repo.transaction(fn ->
        guess =
          Repo.one!(from g in Guess, where: g.id == ^id, lock: "FOR UPDATE")

        cond do
          guess.resolved ->
            {:noop, nil}

          DateTime.compare(DateTime.utc_now(), guess.eligibility_ts) == :lt ->
            {:reschedule_at, guess.eligibility_ts}

          true ->
            resolve(guess)
        end
      end)

    case result do
      {:ok, {:resolved, %{player_id: pid, guess_id: gid}}} ->
        Phoenix.PubSub.broadcast(BtcGuess.PubSub, "player:" <> pid, {:guess_resolved, gid})
        :ok

      {:ok, {:reschedule_at, at}} ->
        Oban.insert!(new(%{"guess_id" => id}, scheduled_at: at))
        :ok

      {:ok, {:retry, _}} ->
        delay = min(@backoff_seconds * attempt, @cap_seconds)

        Oban.insert!(
          new(%{"guess_id" => id}, scheduled_at: DateTime.add(DateTime.utc_now(), delay, :second))
        )

        :ok

      _ ->
        :ok
    end
  end

  defp resolve(guess) do
    case BtcGuess.Price.latest_after(guess.eligibility_ts) do
      {:ok, %{price: price, source: source, received_at: received_at}} ->
        case Outcome.evaluate(guess.direction, guess.entry_price, price) do
          :no_change ->
            {:retry, nil}

          out ->
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

            from(p in BtcGuess.Players.Player, where: p.id == ^guess.player_id)
            |> Repo.update_all(inc: [score: inc])

            {:resolved, %{player_id: guess.player_id, guess_id: guess.id}}
        end

      {:error, _} ->
        {:retry, nil}
    end
  end
end
