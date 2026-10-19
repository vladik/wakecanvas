defmodule WakeCanvasWeb.QrController do
  use WakeCanvasWeb, :controller

  @max_path_bytes 512

  def show(conn, %{"path" => path}) do
    with :ok <- validate_path(path) do
      svg =
        conn
        |> absolute_url(path)
        |> EQRCode.encode()
        |> EQRCode.svg(width: 320, background_color: "#ffffff", color: "#17211d")

      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("cache-control", "private, max-age=300")
      |> send_resp(:ok, svg)
    else
      _ -> send_resp(conn, :bad_request, "Invalid local QR path")
    end
  end

  def show(conn, _params), do: send_resp(conn, :bad_request, "Missing local QR path")

  defp validate_path(path) when is_binary(path) do
    if byte_size(path) <= @max_path_bytes and String.starts_with?(path, "/") and
         not String.starts_with?(path, "//") and not String.contains?(path, ["\r", "\n"]),
       do: :ok,
       else: {:error, :invalid_path}
  end

  defp validate_path(_path), do: {:error, :invalid_path}

  defp absolute_url(conn, path) do
    default_port =
      (conn.scheme == :https and conn.port == 443) or (conn.scheme == :http and conn.port == 80)

    authority = if default_port, do: conn.host, else: "#{conn.host}:#{conn.port}"
    "#{conn.scheme}://#{authority}#{path}"
  end
end
