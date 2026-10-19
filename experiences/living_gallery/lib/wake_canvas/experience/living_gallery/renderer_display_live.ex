defmodule WakeCanvas.Experience.LivingGallery.RendererDisplayLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.LivingGallery.Store

  @impl true
  def mount(_params, session, socket) do
    topic = "living-gallery:#{session["instance_id"]}"
    if connected?(socket), do: Phoenix.PubSub.subscribe(session["pubsub_server"], topic)

    {:ok,
     socket
     |> assign(:page_title, session["instance_name"] || "Living Gallery")
     |> assign(:instance_id, session["instance_id"])
     |> assign(:renderer_diagnostics_api, session["renderer_diagnostics_api"])
     |> assign(:instance_name, session["instance_name"] || "Living Gallery")
     |> assign(:display_variant, session["display_variant"] || "living-collage")
     |> assign(:renderer_url, session["renderer_url"])
     |> assign(:renderer_capabilities, session["renderer_capabilities"] || [])
     |> assign(:renderer_fallback_variant, session["renderer_fallback_variant"])
     |> assign(:renderer_fallback_url, session["renderer_fallback_url"])
     |> assign(:stylesheet_url, session["experience_stylesheet_url"])
     |> assign(:database_path, session["database_path"])
     |> assign(:media_base_url, session["media_base_url"])
     |> load_items()}
  end

  @impl true
  def handle_event("renderer:diagnostic", payload, socket) do
    case socket.assigns.renderer_diagnostics_api do
      api when is_atom(api) ->
        if function_exported?(api, :report, 2),
          do: api.report(socket.assigns.instance_id, payload)

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:media_changed, socket) do
    socket = load_items(socket)
    {:noreply, push_event(socket, "experience:snapshot", renderer_context(socket.assigns))}
  end

  defp load_items(socket) do
    items = Store.list(socket.assigns.database_path, "published")

    assign(socket,
      moments: Enum.filter(items, &(&1.kind == "workshop_moment")) |> Enum.take(12),
      artworks: Enum.filter(items, &(&1.kind == "artwork")) |> Enum.take(40),
      messages: Store.list_messages(socket.assigns.database_path, "published") |> Enum.take(30)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link :if={@stylesheet_url} rel="stylesheet" href={@stylesheet_url} />
    <div
      id="living-gallery-renderer"
      phx-hook="ExperienceRenderer"
      phx-update="ignore"
      data-wakecanvas-experience="living-gallery"
      data-display-variant={@display_variant}
      data-renderer-url={@renderer_url}
      data-renderer-capabilities={Jason.encode!(@renderer_capabilities)}
      data-renderer-fallback-variant={@renderer_fallback_variant}
      data-renderer-fallback-url={@renderer_fallback_url}
      data-renderer-context={Jason.encode!(renderer_context(assigns))}
    >
      <div class="lg-renderer-loading">Preparing {@instance_name}…</div>
    </div>
    """
  end

  defp renderer_context(assigns) do
    %{
      instanceId: assigns.instance_id,
      instanceName: assigns.instance_name,
      variant: assigns.display_variant,
      moments: Enum.map(assigns.moments, &serialize_item(&1, assigns.media_base_url)),
      artworks: Enum.map(assigns.artworks, &serialize_item(&1, assigns.media_base_url)),
      messages: Enum.map(assigns.messages, &serialize_message/1)
    }
  end

  defp serialize_item(item, media_base_url) do
    %{
      id: item.id,
      title: item.title,
      creatorName: item.creator_name,
      showAttribution: item.show_attribution,
      url: "#{media_base_url}/#{item.filename}"
    }
  end

  defp serialize_message(message) do
    %{
      id: message.id,
      body: message.body,
      authorName: message.author_name,
      showAttribution: message.show_attribution
    }
  end
end
