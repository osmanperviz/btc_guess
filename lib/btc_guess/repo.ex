defmodule BtcGuess.Repo do
  use Ecto.Repo,
    otp_app: :btc_guess,
    adapter: Ecto.Adapters.Postgres
end
