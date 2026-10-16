defmodule WakeCanvasWeb.PageControllerTest do
  use WakeCanvasWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/manage"
  end
end
