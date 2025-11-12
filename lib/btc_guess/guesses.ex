defmodule BtcGuess.Guesses do
  import Ecto.Query
  alias BtcGuess.{Repo}
  alias BtcGuess.Players.Player
  alias BtcGuess.Guesses.Guess
  alias BtcGuess.Guesses.Jobs.GuessEligibilityJob

  def ensure_player!(player_id) do
    Repo.insert(%Player{id: player_id}, on_conflict: :nothing, conflict_target: :id)
    Repo.get!(Player, player_id)
  end

  def open_guess_for(player_id) do
    Repo.one(from g in Guess, where: g.player_id == ^player_id and g.resolved == false)
  end

  def last_guesses(player_id, n \\ 5) do
    from(g in Guess,
      where: g.player_id == ^player_id and g.resolved == true,
      order_by: [desc: g.inserted_at],
      limit: ^n
    )
    |> Repo.all()
  end

  def place_guess!(player_id, direction) when direction in ["up", "down"] do
    {:ok, %{price: price}} = BtcGuess.Price.latest()

    now = DateTime.utc_now()
    elig = DateTime.add(now, 60, :second)

    changeset =
      Guess.create_changeset(%Guess{}, %{
        player_id: player_id,
        direction: direction,
        entry_price: price,
        placed_at: now,
        eligibility_ts: elig
      })

    guess = Repo.insert!(changeset)

    Oban.insert!(GuessEligibilityJob.new(%{"guess_id" => guess.id}, scheduled_at: elig))

    Phoenix.PubSub.broadcast(BtcGuess.PubSub, "player:" <> player_id, {:guess_placed, guess.id})

    guess
  end
end
