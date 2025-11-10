defmodule BtcGuess.Guesses.OutcomeTest do
  use ExUnit.Case, async: true

  alias BtcGuess.Guesses.Outcome

  describe "evaluate/3" do
    test "returns :win when guessing up and price increases" do
      entry = Decimal.new("100000")
      resolve = Decimal.new("100001")

      assert Outcome.evaluate(:up, entry, resolve) == :win
    end

    test "returns :lose when guessing up and price decreases" do
      entry = Decimal.new("100000")
      resolve = Decimal.new("99999")

      assert Outcome.evaluate(:up, entry, resolve) == :lose
    end

    test "returns :win when guessing down and price decreases" do
      entry = Decimal.new("100000")
      resolve = Decimal.new("99999")

      assert Outcome.evaluate(:down, entry, resolve) == :win
    end

    test "returns :lose when guessing down and price increases" do
      entry = Decimal.new("100000")
      resolve = Decimal.new("100001")

      assert Outcome.evaluate(:down, entry, resolve) == :lose
    end

    test "returns :no_change when prices are equal" do
      entry = Decimal.new("100000")
      resolve = Decimal.new("100000")

      assert Outcome.evaluate(:up, entry, resolve) == :no_change
      assert Outcome.evaluate(:down, entry, resolve) == :no_change
    end

    test "handles large price differences" do
      entry = Decimal.new("100000")
      resolve = Decimal.new("150000")

      assert Outcome.evaluate(:up, entry, resolve) == :win
      assert Outcome.evaluate(:down, entry, resolve) == :lose
    end

    test "handles small price differences" do
      entry = Decimal.new("100000.00")
      resolve = Decimal.new("100000.01")

      assert Outcome.evaluate(:up, entry, resolve) == :win
      assert Outcome.evaluate(:down, entry, resolve) == :lose
    end
  end
end
