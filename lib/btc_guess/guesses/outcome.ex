defmodule BtcGuess.Guesses.Outcome do
  @moduledoc """
  Determines the result of a player's guess.

  This module compares the entry price (when the player guessed) with
  the resolved price (after 60 seconds) and returns whether the player
  **won** or **lost** the round.

  ## Logic

    * If `resolve_price` > `entry_price` and the player guessed `"up"`, it's a win.
    * If `resolve_price` < `entry_price` and the player guessed `"down"`, it's a win.
    * If prices are equal, or the direction was wrong, it's a loss.

  The module exposes a simple function:

      iex> Outcome.evaluate("up", Decimal.new("64000.00"), Decimal.new("64010.00"))
      :win

      iex> Outcome.evaluate("down", Decimal.new("64000.00"), Decimal.new("64010.00"))
      :lose

  This logic is used by the background job that resolves guesses.
  """
  def evaluate(direction, entry, now_price) do
    cond do
      Decimal.eq?(now_price, entry) -> :no_change
      direction == "up" and Decimal.gt?(now_price, entry) -> :win
      direction == "down" and Decimal.lt?(now_price, entry) -> :win
      true -> :lose
    end
  end
end
