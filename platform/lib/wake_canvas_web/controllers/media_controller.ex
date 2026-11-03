defmodule WakeCanvasWeb.MediaController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.InstancePaths

  def show(conn, %{"instance_id" => id, "filename" => filename}) do
    with instance when not is_nil(instance) <- Experiences.get_instance(id),
         true <- safe_filename?(filename),
         path = Path.join(InstancePaths.media_dir(instance.id), filename),
         {:ok, stat} <- File.stat(path),
         true <- stat.type == :regular do
      serve_media(conn, path, filename, stat.size)
    else
      _ -> send_resp(conn, :not_found, "Media not found")
    end
  end

  defp serve_media(conn, path, filename, size) do
    conn =
      conn
      |> put_resp_content_type(MIME.from_path(filename))
      |> put_resp_header("accept-ranges", "bytes")

    case get_req_header(conn, "range") do
      [range] -> serve_range(conn, path, range, size)
      _ -> send_file(conn, 200, path)
    end
  end

  defp serve_range(conn, path, "bytes=" <> range, size) do
    case parse_range(range, size) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")

      :invalid ->
        send_file(conn, 200, path)
    end
  end

  defp serve_range(conn, path, _range, _size), do: send_file(conn, 200, path)

  defp parse_range(range, size) when size > 0 do
    case String.split(range, "-", parts: 2) do
      ["", suffix] ->
        with {length, ""} when length > 0 <- Integer.parse(suffix) do
          first = max(0, size - min(length, size))
          {:ok, first, size - 1}
        else
          _ -> :invalid
        end

      [first, ""] ->
        with {offset, ""} when offset >= 0 <- Integer.parse(first) do
          if offset < size, do: {:ok, offset, size - 1}, else: :unsatisfiable
        else
          _ -> :invalid
        end

      [first, last] ->
        with {offset, ""} when offset >= 0 <- Integer.parse(first),
             {finish, ""} when finish >= offset <- Integer.parse(last) do
          if offset < size,
            do: {:ok, offset, min(finish, size - 1)},
            else: :unsatisfiable
        else
          _ -> :invalid
        end

      _ ->
        :invalid
    end
  end

  defp parse_range(_range, _size), do: :unsatisfiable

  defp safe_filename?(filename),
    do: filename == Path.basename(filename) and filename not in [".", ".."]
end
