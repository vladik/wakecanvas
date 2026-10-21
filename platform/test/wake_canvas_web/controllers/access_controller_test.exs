defmodule WakeCanvasWeb.AccessControllerTest do
  use WakeCanvasWeb.ConnCase

  setup do
    previous = Application.get_env(:wake_canvas, :management_code, "")
    Application.put_env(:wake_canvas, :management_code, "123456")
    on_exit(fn -> Application.put_env(:wake_canvas, :management_code, previous) end)
    :ok
  end

  test "management routes redirect to the friendly code form", %{conn: conn} do
    conn = get(conn, ~p"/manage")
    assert redirected_to(conn) == "/access/manage?return_to=%2Fmanage"

    conn = get(build_conn(), ~p"/access/manage")
    assert html_response(conn, 200) =~ "Enter the six-digit management code"
  end

  test "a valid management session reaches management", %{conn: conn} do
    conn =
      conn |> init_test_session(%{"wakecanvas_management_access" => true}) |> get(~p"/manage")

    assert html_response(conn, 200) =~ "Kiosk management"
  end
end
