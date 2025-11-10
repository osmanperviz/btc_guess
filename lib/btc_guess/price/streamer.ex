defmodule BtcGuess.Price.Streamer do
  @moduledoc """
  Single Coinbase BTC-USD WebSocket stream.
  Updates cache and broadcasts on 'price:ticker' topic.
  """
  use WebSockex
  require Logger
  alias BtcGuess.Price.Cache

  @url "wss://ws-feed.exchange.coinbase.com"

  def start_link(_) do
    WebSockex.start_link(@url, __MODULE__, %{}, name: __MODULE__)
  end

  def handle_connect(_conn, state) do
    Logger.info("Price.Streamer connected to Coinbase WebSocket")
    send(self(), :subscribe)
    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    with {:ok, %{"type" => "ticker", "price" => price_str, "time" => iso}} <- Jason.decode(msg),
         {:ok, price} <- Decimal.cast(price_str),
         true <- Decimal.compare(price, 0) == :gt,
         {:ok, exch_ts, _} <- DateTime.from_iso8601(iso) do
      price_data = %{
        price: price,
        source: :ws,
        exchange_ts: exch_ts,
        received_at: DateTime.utc_now()
      }

      Cache.put(price_data)
      Phoenix.PubSub.broadcast(BtcGuess.PubSub, "price:ticker", {:price, price_data})
    else
      _ -> :ok
    end

    {:ok, state}
  end

  def handle_disconnect(reason, state) do
    Logger.warning("Price.Streamer disconnected: #{inspect(reason)}")
    Process.send_after(self(), :reconnect, 1_000 + :rand.uniform(4_000))
    {:ok, state}
  end

  def handle_info(:subscribe, state) do
    sub = %{
      "type" => "subscribe",
      "channels" => [%{"name" => "ticker", "product_ids" => ["BTC-USD"]}]
    }

    {:reply, {:text, Jason.encode!(sub)}, state}
  end

  def handle_info(:reconnect, state) do
    Logger.info("Price.Streamer attempting to reconnect...")
    {:reconnect, state}
  end
end
