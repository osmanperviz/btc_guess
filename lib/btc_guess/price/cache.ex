defmodule BtcGuess.Price.Cache do
  @moduledoc """
  A lightweight in-memory cache that stores the most recently fetched BTC/USD price.

  ## Purpose

  The guessing game occasionally needs to know the current Bitcoin price — both when a
  player places a guess and when a background job resolves it later. Instead of calling
  the external API every time, we keep the **latest known price** in memory and reuse it
  while it’s still fresh.

  This cache helps:
  - reduce external API calls,
  - provide instant access to the most recent price,
  - give a fallback value if the external API briefly fails.

  ## How it works

  - It runs as a simple `GenServer` registered under `BtcGuess.Price.Cache`.
  - It holds a single map like:
    %{
      price: Decimal.t(),
      source: "rest" | "ws",
      exchange_ts: DateTime.t() | nil,
      received_at: DateTime.t()
    }
  - `put/1` replaces the stored value.
  - `latest/0` returns the current value (or `{}` if nothing cached yet).

  The module doesn’t fetch prices itself — it only stores them. Actual fetching is done
  by `BtcGuess.Price`, which updates this cache whenever it receives new data from the
  external API or WebSocket feed.

  ## Lifetime & persistence

  The cache lives only in memory. It resets when the application restarts.
  This is acceptable because the next price request will repopulate it from the API.

  ## Example

      iex> BtcGuess.Price.Cache.put(%{price: Decimal.new("64200.12"), source: "rest"})
      :ok
      iex> BtcGuess.Price.Cache.latest()
      %{price: Decimal.new("64200.12"), source: "rest"}

  """
  use GenServer
  @name __MODULE__

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: @name)
  def init(state), do: {:ok, state}

  def put(price_map), do: GenServer.cast(@name, {:put, price_map})
  def latest, do: GenServer.call(@name, :latest)

  def handle_cast({:put, price_map}, _), do: {:noreply, price_map}
  def handle_call(:latest, _from, state), do: {:reply, state, state}
end
