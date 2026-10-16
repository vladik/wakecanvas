defmodule WakeCanvasWeb.PageController do
  use WakeCanvasWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/manage")
  end
end
