defmodule BtcGuessWeb.ErrorJSONTest do
  use BtcGuessWeb.ConnCase, async: true

  test "renders 404" do
    assert BtcGuessWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert BtcGuessWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
