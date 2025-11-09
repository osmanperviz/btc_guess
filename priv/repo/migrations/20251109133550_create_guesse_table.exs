defmodule BtcGuess.Repo.Migrations.CreateGuesseTable do
  use Ecto.Migration

  def change do
    create table(:guesses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :player_id, references(:players, type: :uuid, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :entry_price, :decimal, null: false
      add :placed_at, :utc_datetime_usec, null: false
      add :eligibility_ts, :utc_datetime_usec, null: false
      add :resolved, :boolean, null: false, default: false
      add :resolve_price, :decimal
      add :resolve_ts, :utc_datetime_usec
      add :source, :string
      add :outcome, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:guesses, [:player_id])

    # One open guess per player
    create unique_index(:guesses, [:player_id],
             where: "resolved = false",
             name: :uniq_open_guess_per_player
           )
  end
end
