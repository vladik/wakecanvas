defmodule WakeCanvasWeb.QrControllerTest do
  use WakeCanvasWeb.ConnCase

  test "renders an offline SVG QR code for a local path", %{conn: conn} do
    conn =
      conn
      |> authorize_management()
      |> get(~p"/manage/qr?#{[path: "/i/550e8400-e29b-41d4-a716-446655440000/artwork"]}")

    assert response_content_type(conn, :svg) == "image/svg+xml; charset=utf-8"
    assert response(conn, 200) =~ "<svg"
  end

  test "rejects external and protocol-relative destinations", %{conn: conn} do
    conn = conn |> authorize_management() |> get(~p"/manage/qr?#{[path: "//example.com"]}")
    assert response(conn, 400) == "Invalid local QR path"
  end

  defp authorize_management(conn) do
    conn
    |> init_test_session(%{})
    |> put_session("wakecanvas_management_access", true)
  end
end
