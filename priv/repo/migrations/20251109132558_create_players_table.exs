defmodule BtcGuess.Repo.Migrations.CreatePlayersTable do
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :score, :integer, default: 0, null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
