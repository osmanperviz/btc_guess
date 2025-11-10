defmodule BtcGuessWeb.Router do
  use BtcGuessWeb, :router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BtcGuessWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BtcGuessWeb.UserIdPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", BtcGuessWeb do
    pipe_through :api
  end

  scope "/", BtcGuessWeb do
    pipe_through :browser

    live "/", GameLive
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:btc_guess, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: BtcGuessWeb.Telemetry
    end
  end
end
