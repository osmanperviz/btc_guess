defmodule BtcGuess.Price do
  @moduledoc """
    Fetches BTC-USD from a public REST endpoint; caches the latest.
  """

  # Coinbase spot price
  @url "https://api.coinbase.com/v2/prices/BTC-USD/spot"

  def latest() do
    # Try cache first
    case BtcGuess.Price.Cache.latest() do
      %{price: price} = p when not is_nil(price) -> {:ok, p}
      _ -> fetch_rest()
    end
  end

  def latest_after(_ts) do
    fetch_rest()
  end

  defp fetch_rest() do
    req = Finch.build(:get, @url, [{"accept", "application/json"}])

    with {:ok, %Finch.Response{status: 200, body: body}} <- Finch.request(req, BtcGuessFinch),
         {:ok, %{"data" => %{"amount" => amount}}} <- Jason.decode(body),
         {:ok, dec} <- Decimal.cast(amount),
         true <- Decimal.compare(dec, 0) == :gt do
      map = %{price: dec, source: :rest, exchange_ts: nil, received_at: DateTime.utc_now()}
      BtcGuess.Price.Cache.put(map)
      {:ok, map}
    else
      _ -> {:error, :fetch_failed}
    end
  end
end
