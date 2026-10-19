defmodule WakeCanvasWeb.Plugs.RequireManagementAccess do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias WakeCanvas.Access

  def init(options), do: options

  def call(conn, _options) do
    if Access.management_authorized?(conn) do
      conn
    else
      conn
      |> redirect(to: "/access/manage?return_to=#{URI.encode_www_form(conn.request_path)}")
      |> halt()
    end
  end
end
