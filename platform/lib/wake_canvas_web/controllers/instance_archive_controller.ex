defmodule WakeCanvasWeb.InstanceArchiveController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Experiences

  def export(conn, %{"id" => id}) do
    case Experiences.export_instance(id) do
      {:ok, archive} ->
        conn =
          send_download(conn, {:file, archive.path},
            filename: archive.filename,
            content_type: "application/vnd.wakecanvas.instance+zip"
          )

        _ = File.rm(archive.path)
        conn

      {:error, :not_archived} ->
        conn
        |> put_flash(:error, "Archive the instance before exporting it.")
        |> redirect(to: ~p"/manage")

      {:error, :not_found} ->
        send_resp(conn, :not_found, "Instance not found")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Could not export the instance: #{inspect(reason)}")
        |> redirect(to: ~p"/manage")
    end
  end
end
