defmodule BtcGuess.Players.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :score, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(player, attrs), do: cast(player, attrs, [:score])
end
