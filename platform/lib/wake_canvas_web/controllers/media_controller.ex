defmodule WakeCanvasWeb.MediaController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.InstancePaths

  def show(conn, %{"instance_id" => id, "filename" => filename}) do
    with {instance_id, ""} <- Integer.parse(id),
         instance when not is_nil(instance) <- Experiences.get_instance(instance_id),
         true <- safe_filename?(filename),
         path = Path.join(InstancePaths.media_dir(instance.id), filename),
         true <- File.regular?(path) do
      send_download(conn, {:file, path}, disposition: :inline, filename: filename)
    else
      _ -> send_resp(conn, :not_found, "Media not found")
    end
  end

  defp safe_filename?(filename),
    do: filename == Path.basename(filename) and filename not in [".", ".."]
end
