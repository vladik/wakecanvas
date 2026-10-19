defmodule WakeCanvasWeb.ExperienceAssetController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Experiences.Registry

  def show(conn, %{"experience_id" => experience_id, "path" => segments}) do
    with {:ok, definition} <- Registry.definition(experience_id),
         {:ok, priv_dir} <- application_priv_dir(definition.otp_application),
         {:ok, path} <- safe_asset_path(priv_dir, segments),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path))
      |> send_file(200, path)
    else
      _ -> send_resp(conn, :not_found, "Experience asset not found")
    end
  end

  defp application_priv_dir(application) do
    case :code.priv_dir(application) do
      path when is_list(path) -> {:ok, List.to_string(path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_asset_path(priv_dir, segments) when is_list(segments) do
    root = Path.expand(priv_dir)
    candidate = segments |> Path.join() |> then(&Path.expand(&1, root))
    relative = Path.relative_to(candidate, root)
    relative_parts = Path.split(relative)

    if candidate != root and Path.type(relative) == :relative and
         List.first(relative_parts) != "..",
       do: {:ok, candidate},
       else: {:error, :invalid_path}
  end
end
