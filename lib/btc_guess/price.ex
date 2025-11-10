defmodule BtcGuess.Price do
  @moduledoc """
  Public interface for current BTC/USD price with cache + REST fallback.
  """
  alias BtcGuess.Price.Cache

  @rest_url "https://api.coinbase.com/v2/prices/BTC-USD/spot"
  @fresh_secs 15

  def latest() do
    case Cache.latest() do
      %{price: _p, received_at: ts} = cached when not is_nil(ts) ->
        if fresh?(ts), do: {:ok, cached}, else: fetch_rest()

      _ ->
        fetch_rest()
    end
  end

  def latest_after(_ts), do: fetch_rest()

  defp fresh?(ts), do: DateTime.diff(DateTime.utc_now(), ts, :second) < @fresh_secs

  defp fetch_rest() do
    req = Finch.build(:get, @rest_url, [{"accept", "application/json"}])

    with {:ok, %Finch.Response{status: 200, body: body}} <-
           Finch.request(req, BtcGuessFinch, receive_timeout: 2_000),
         {:ok, %{"data" => %{"amount" => amount}}} <- Jason.decode(body),
         {:ok, dec} <- Decimal.cast(amount),
         true <- Decimal.compare(dec, 0) == :gt do
      map = %{price: dec, source: :rest, exchange_ts: nil, received_at: DateTime.utc_now()}
      Cache.put(map)
      {:ok, map}
    else
      _ -> {:error, :fetch_failed}
    end
  end
end
