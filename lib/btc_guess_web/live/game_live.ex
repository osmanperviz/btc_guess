defmodule BtcGuessWeb.GameLive do
  use BtcGuessWeb, :live_view

  alias BtcGuess.Guesses
  alias BtcGuess.Repo

  require Logger

  @impl true
  def mount(_params, session, socket) do
    player_id = session["user_id"]
    player = Guesses.ensure_player!(player_id)

    # Subscribe to player-specific events and price updates
    Phoenix.PubSub.subscribe(BtcGuess.PubSub, "player:" <> player_id)
    Phoenix.PubSub.subscribe(BtcGuess.PubSub, "price:ticker")

    open = Guesses.open_guess_for(player_id)
    history = Guesses.last_guesses(player_id)

    # Start countdown timer if there's an open guess
    if open do
      schedule_tick()
    end

    latest_price =
      case BtcGuess.Price.latest() do
        {:ok, %{price: p}} -> p
        _ -> nil
      end

    {:ok,
     socket
     |> assign(:player, player)
     |> assign(:open_guess, open)
     |> assign(:history, history)
     |> assign(:latest_price, latest_price)
     |> assign(:current_time, DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
      <div class="max-w-2xl w-full">
        <!-- Header Card -->
        <div class="bg-white rounded-2xl shadow-xl p-8 mb-6">
          <h1 class="text-4xl font-bold text-center text-gray-800 mb-6">🪙 BTC Price Guess</h1>

          <div class="grid grid-cols-2 gap-4 mb-6">
            <div class="bg-blue-50 rounded-xl p-4 text-center">
              <p class="text-sm text-gray-600 mb-1">Current Price</p>
              <p class="text-2xl font-bold text-blue-600">${format_price(@latest_price)}</p>
            </div>
            <div class="bg-green-50 rounded-xl p-4 text-center">
              <p class="text-sm text-gray-600 mb-1">Your Score</p>
              <p class="text-2xl font-bold text-green-600">{@player.score}</p>
            </div>
          </div>

          <!-- Guess Buttons -->
          <div class="flex gap-4">
            <button
              phx-click="guess"
              phx-value-dir="up"
              disabled={not is_nil(@open_guess)}
              class="flex-1 bg-green-500 hover:bg-green-600 disabled:bg-gray-300 disabled:cursor-not-allowed text-white font-bold py-4 px-6 rounded-xl transition-all transform hover:scale-105 active:scale-95 shadow-lg"
            >
              📈 UP
            </button>
            <button
              phx-click="guess"
              phx-value-dir="down"
              disabled={not is_nil(@open_guess)}
              class="flex-1 bg-red-500 hover:bg-red-600 disabled:bg-gray-300 disabled:cursor-not-allowed text-white font-bold py-4 px-6 rounded-xl transition-all transform hover:scale-105 active:scale-95 shadow-lg"
            >
              📉 DOWN
            </button>
          </div>

          <!-- Open Guess Status -->
          <div :if={@open_guess} class="mt-6 bg-gradient-to-r from-yellow-100 to-orange-100 border-4 border-yellow-400 rounded-2xl p-6 shadow-2xl animate-pulse">
            <div class="flex items-center justify-center gap-3 mb-4">
              <span class="text-4xl">⏳</span>
              <h3 class="text-2xl font-bold text-yellow-900">GUESS IN PROGRESS</h3>
              <span class="text-4xl">⏳</span>
            </div>

            <div class="bg-white/80 rounded-xl p-4 mb-4">
              <div class="grid grid-cols-2 gap-4 text-center">
                <div>
                  <p class="text-xs text-gray-600 uppercase mb-1">Your Prediction</p>
                  <p class={[
                    "text-3xl font-black",
                    @open_guess.direction == :up && "text-green-600",
                    @open_guess.direction == :down && "text-red-600"
                  ]}>
                    {if @open_guess.direction == :up, do: "📈 UP", else: "📉 DOWN"}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-gray-600 uppercase mb-1">Entry Price</p>
                  <p class="text-2xl font-bold text-blue-600">${format_price(@open_guess.entry_price)}</p>
                </div>
              </div>
            </div>

            <div class="text-center">
              <p class="text-sm font-semibold text-yellow-900 mb-1">⏰ Resolves at: {format_time(@open_guess.eligibility_ts)}</p>
              <p class="text-lg font-bold text-orange-700 animate-bounce">🔄 {get_status_message(@open_guess.eligibility_ts, @current_time)}</p>
              <p class="text-xs text-gray-600 mt-2">Your guess will be resolved once the price moves</p>
            </div>
          </div>
        </div>

        <!-- History Card -->
        <div class="bg-white rounded-2xl shadow-xl p-8">
          <h2 class="text-2xl font-bold text-gray-800 mb-4">📊 Recent Rounds</h2>

          <div :if={@history == []} class="text-center text-gray-500 py-8">
            No rounds yet. Make your first guess!
          </div>

          <div :if={@history != []} class="space-y-3">
            <div :for={g <- @history} class="bg-gray-50 rounded-lg p-4 hover:bg-gray-100 transition-colors">
              <div class="flex items-center justify-between">
                <div class="flex-1">
                  <div class="flex items-center gap-2 mb-1">
                    <span class={[
                      "font-bold text-lg",
                      g.outcome == :win && "text-green-600",
                      g.outcome == :lose && "text-red-600"
                    ]}>
                      {if g.outcome == :win, do: "✅ WIN", else: "❌ LOSE"}
                    </span>
                    <span class="text-sm text-gray-500">{format_time(g.inserted_at)}</span>
                  </div>
                  <div class="text-sm text-gray-600">
                    <span class="font-medium">{String.upcase(to_string(g.direction))}</span>
                    <span class="mx-2">•</span>
                    <span>${format_price(g.entry_price)} → ${format_price(g.resolve_price)}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_price(nil), do: "..."

  defp format_price(price) when is_struct(price, Decimal) do
    price
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_time(nil), do: ""

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%b %d, %H:%M:%S")
  end

  defp get_status_message(eligibility_ts, current_time) do
    diff = DateTime.diff(eligibility_ts, current_time)

    cond do
      diff > 0 ->
        minutes = div(diff, 60)
        seconds = rem(diff, 60)
        "Resolves in #{minutes}m #{seconds}s"

      true ->
        "Waiting for price to change..."
    end
  end

  @impl true
  def handle_event("guess", %{"dir" => dir}, socket) do
    require Logger
    Logger.info("Guess button clicked: #{dir}")

    if socket.assigns.open_guess do
      {:noreply, socket}
    else
      try do
        guess = Guesses.place_guess!(socket.assigns.player.id, dir)
        Logger.info("Guess placed successfully: #{guess.id}")
        # Start countdown timer
        schedule_tick()
        {:noreply, assign(socket, open_guess: guess)}
      rescue
        e ->
          Logger.error("Failed to place guess: #{inspect(e)}")
          {:noreply, put_flash(socket, :error, "Failed to place guess: #{Exception.message(e)}")}
      end
    end
  end

  @impl true
  def handle_info({:price, %{price: price}}, socket) do
    {:noreply, assign(socket, :latest_price, price)}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Update current time for countdown
    socket = assign(socket, :current_time, DateTime.utc_now())

    # Keep ticking if there's still an open guess
    if socket.assigns.open_guess do
      schedule_tick()
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:guess_placed, guess_id}, socket) do
    Logger.info("Received guess_placed for #{guess_id}")

    player_id = socket.assigns.player.id

    open = Guesses.open_guess_for(player_id)

    if open do
      schedule_tick()
    end

    {:noreply, assign(socket, open_guess: open)}
  end

  @impl true
  def handle_info({:guess_resolved, guess_id}, socket) do
    Logger.info("Received guess_resolved for #{guess_id}")

    player_id = socket.assigns.player.id

    # Reload all data from database
    player = Repo.get!(BtcGuess.Players.Player, player_id)
    open = Guesses.open_guess_for(player_id)
    history = Guesses.last_guesses(player_id)

    Logger.info(
      "Player score: #{player.score}, Open guess: #{inspect(open)}, History count: #{length(history)}"
    )

    {:noreply,
     socket
     |> assign(player: player, open_guess: open, history: history)
     |> put_flash(:info, "Guess resolved!")}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, 1000)
  end
end
