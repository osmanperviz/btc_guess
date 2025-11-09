defmodule BtcGuess.Guesses.Guess do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @directions ~w(up down)a
  @sources ~w(ws rest)a
  @outcomes ~w(win lose)a

  schema "guesses" do
    field :direction, Ecto.Enum, values: @directions
    field :entry_price, :decimal
    field :placed_at, :utc_datetime_usec
    field :eligibility_ts, :utc_datetime_usec
    field :resolved, :boolean, default: false
    field :resolve_price, :decimal
    field :resolve_ts, :utc_datetime_usec
    field :source, Ecto.Enum, values: @sources
    field :outcome, Ecto.Enum, values: @outcomes

    belongs_to :player, BtcGuess.Players.Player, type: :binary_id
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(guess, attrs) do
    guess
    |> cast(attrs, [:player_id, :direction, :entry_price, :placed_at, :eligibility_ts])
    |> validate_required([:player_id, :direction, :entry_price, :placed_at, :eligibility_ts])
    |> validate_inclusion(:direction, @directions)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:outcome, @outcomes)
  end
end
