defmodule BtcGuessWeb.UserIdPlug do
  import Plug.Conn
  @cookie "user_id"
  # 5 years
  @max_age 60 * 60 * 24 * 365 * 5

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    case conn.cookies[@cookie] do
      nil ->
        user_id = Ecto.UUID.generate()

        conn
        |> put_resp_cookie(@cookie, user_id, http_only: true, max_age: @max_age)
        |> assign(:user_id, user_id)

      user_id ->
        assign(conn, :user_id, user_id)
    end
  end
end
