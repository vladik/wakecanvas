defmodule WakeCanvasWeb.SurfaceController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.InstancePaths
  alias WakeCanvas.Experiences.Registry

  def show(conn, %{"instance_id" => id, "surface" => path} = params) do
    with {instance_id, ""} <- Integer.parse(id),
         instance when not is_nil(instance) <- Experiences.get_instance(instance_id),
         {:ok, surface} <- Registry.surface(instance.experience_id, path),
         {:ok, variant} <- resolve_variant(instance, surface, params) do
      InstancePaths.ensure!(instance.id)

      Phoenix.LiveView.Controller.live_render(conn, surface.module,
        session: surface_session(instance, variant)
      )
    else
      _ -> send_resp(conn, :not_found, "Experience surface not found")
    end
  end

  defp resolve_variant(instance, %{role: :display}, params) do
    case Map.get(params, "variant") do
      nil -> configured_variant_or_default(instance)
      requested -> Registry.display_variant(instance.experience_id, requested)
    end
  end

  defp resolve_variant(_instance, _surface, _params), do: {:ok, nil}

  defp configured_variant_or_default(instance) do
    configured = Map.get(instance.config, "display_variant")

    case Registry.display_variant(instance.experience_id, configured) do
      {:error, :unknown_display_variant} -> Registry.display_variant(instance.experience_id)
      result -> result
    end
  end

  defp surface_session(instance, variant) do
    %{
      "instance_id" => instance.id,
      "instance_name" => instance.name,
      "experience_id" => instance.experience_id,
      "config" => instance.config,
      "data_dir" => InstancePaths.data_dir(instance.id),
      "database_path" => InstancePaths.database_path(instance.id),
      "media_base_url" => "/media/instances/#{instance.id}",
      "pubsub_server" => WakeCanvas.PubSub,
      "config_api" => WakeCanvas.Experiences.ConfigAPI,
      "display_variant" => variant && variant.id
    }
  end

  def active_display(conn, _params) do
    case Experiences.active_instance() do
      nil -> redirect(conn, to: ~p"/manage")
      instance -> redirect(conn, to: ~p"/i/#{instance.id}/display")
    end
  end
end
