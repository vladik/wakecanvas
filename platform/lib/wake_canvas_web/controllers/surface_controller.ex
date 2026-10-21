defmodule WakeCanvasWeb.SurfaceController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Experiences
  alias WakeCanvas.Access
  alias WakeCanvas.Experiences.InstancePaths
  alias WakeCanvas.Experiences.Registry

  def show(conn, %{"instance_id" => id, "surface" => path} = params) do
    render_surface(conn, id, path, params)
  end

  def show_variant(conn, %{"variant_id" => variant_id} = params) do
    render_surface(conn, params["instance_id"], "display", Map.put(params, "variant", variant_id))
  end

  defp render_surface(conn, instance_reference, path, params) do
    with instance when not is_nil(instance) <- Experiences.get_instance(instance_reference),
         {:ok, surface} <- Registry.surface(instance.experience_id, path),
         :ok <- authorize_surface(conn, instance, surface),
         {:ok, variant} <- resolve_variant(instance, surface, params) do
      InstancePaths.ensure!(instance.id)

      Phoenix.LiveView.Controller.live_render(conn, surface.module,
        session: surface_session(instance, variant)
      )
    else
      {:redirect, destination} -> redirect(conn, to: destination)
      _ -> send_resp(conn, :not_found, "Experience surface not found")
    end
  end

  defp authorize_surface(_conn, _instance, %{role: :display}), do: :ok

  defp authorize_surface(conn, _instance, %{role: :operator}) do
    if Access.management_authorized?(conn),
      do: :ok,
      else: {:redirect, "/access/manage?return_to=#{URI.encode_www_form(conn.request_path)}"}
  end

  defp authorize_surface(conn, instance, %{role: role})
       when role in [:participant, :primary_intake] do
    if Access.participant_authorized?(conn, instance),
      do: :ok,
      else:
        {:redirect,
         "/access/instances/#{instance.id}?return_to=#{URI.encode_www_form(conn.request_path)}"}
  end

  defp authorize_surface(_conn, _instance, _surface), do: :ok

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
    {:ok, definition} = Registry.definition(instance.experience_id)
    asset_base = "/experience-assets/#{definition.id}"
    fallback = fallback_variant(instance.experience_id, variant)
    stylesheet = Map.get(definition, :stylesheet)

    %{
      "instance_id" => instance.id,
      "instance_reference" => Experiences.instance_reference(instance),
      "instance_name" => instance.name,
      "experience_id" => instance.experience_id,
      "config" => instance.config,
      "data_dir" => InstancePaths.data_dir(instance.id),
      "database_path" => InstancePaths.database_path(instance.id),
      "media_base_url" => "/media/instances/#{instance.id}",
      "experience_asset_base_url" => asset_base,
      "pubsub_server" => WakeCanvas.PubSub,
      "config_api" => WakeCanvas.Experiences.ConfigAPI,
      "renderer_diagnostics_api" => WakeCanvas.Diagnostics.RendererMonitor,
      "display_variant" => variant && variant.id,
      "renderer_url" => renderer_url(asset_base, variant),
      "renderer_capabilities" => variant && Map.get(variant, :capabilities, []),
      "renderer_fallback_variant" => fallback && Map.get(fallback, :id),
      "renderer_fallback_url" => renderer_url(asset_base, fallback),
      "experience_stylesheet_url" => stylesheet && "#{asset_base}/#{stylesheet}"
    }
  end

  defp renderer_url(_asset_base, nil), do: nil

  defp renderer_url(asset_base, variant) do
    case Map.get(variant, :entrypoint) do
      entrypoint when is_binary(entrypoint) and entrypoint != "" -> "#{asset_base}/#{entrypoint}"
      _ -> nil
    end
  end

  defp fallback_variant(_experience_id, nil), do: nil

  defp fallback_variant(experience_id, variant) do
    case Map.get(variant, :fallback) do
      fallback_id when is_binary(fallback_id) and fallback_id != "" ->
        case Registry.display_variant(experience_id, fallback_id) do
          {:ok, fallback} -> fallback
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def active_display(conn, _params) do
    case Experiences.active_instance() do
      nil -> redirect(conn, to: ~p"/manage")
      instance -> redirect(conn, to: ~p"/i/#{Experiences.instance_reference(instance)}/display")
    end
  end
end
