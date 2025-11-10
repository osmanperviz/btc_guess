defmodule BtcGuessWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.
  """

  use Phoenix.Component
  import Phoenix.Controller, only: [get_csrf_token: 0]
  use Phoenix.VerifiedRoutes, endpoint: BtcGuessWeb.Endpoint, router: BtcGuessWeb.Router

  embed_templates "layouts/*"
end
