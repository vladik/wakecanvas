defmodule WakeCanvas.Experience.CollectiveForm.DisplayLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.CollectiveForm.{Pareidolia, Store}

  @refresh_interval 2_000

  @impl true
  def mount(_params, session, socket) do
    topic = "collective-form:#{session["instance_id"]}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(session["pubsub_server"], topic)
      schedule_refresh()
    end

    {:ok,
     socket
     |> assign(:instance_id, session["instance_id"])
     |> assign(:instance_name, session["instance_name"] || "Collective Form")
     |> assign(:display_variant, session["display_variant"] || "growing-mycelium")
     |> assign(:renderer_diagnostics_api, session["renderer_diagnostics_api"])
     |> assign(:renderer_url, session["renderer_url"])
     |> assign(:stylesheet_url, session["experience_stylesheet_url"])
     |> assign(:data_dir, session["data_dir"])
     |> assign(:database_path, session["database_path"])
     |> assign(:snapshot, Store.snapshot(session["database_path"]))
     |> assign(
       :pareidolia,
       pareidolia_status(session["display_variant"], session["data_dir"])
     )}
  end

  @impl true
  def handle_info(:table_changed, socket) do
    snapshot = Store.snapshot(socket.assigns.database_path)
    pareidolia = pareidolia_status(socket.assigns.display_variant, socket.assigns.data_dir)

    {:noreply,
     socket
     |> assign(:snapshot, snapshot)
     |> assign(:pareidolia, pareidolia)
     |> push_event(
       "experience:snapshot",
       renderer_context(socket.assigns.instance_name, snapshot, pareidolia)
     )}
  end

  def handle_info(:network_refresh, socket) do
    snapshot = Store.snapshot(socket.assigns.database_path)
    pareidolia = pareidolia_status(socket.assigns.display_variant, socket.assigns.data_dir)
    schedule_refresh()

    if snapshot == socket.assigns.snapshot and pareidolia == socket.assigns.pareidolia do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:snapshot, snapshot)
       |> assign(:pareidolia, pareidolia)
       |> push_event(
         "experience:snapshot",
         renderer_context(socket.assigns.instance_name, snapshot, pareidolia)
       )}
    end
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
  def render(assigns) do
    ~H"""
    <link :if={@stylesheet_url} rel="stylesheet" href={@stylesheet_url} />
    <div
      id="experience-renderer"
      phx-hook="ExperienceRenderer"
      phx-update="ignore"
      data-wakecanvas-experience="collective-form"
      data-display-variant={@display_variant}
      data-renderer-url={@renderer_url}
      data-renderer-capabilities="[]"
      data-renderer-context={Jason.encode!(renderer_context(@instance_name, @snapshot, @pareidolia))}
    >
      <p class="experience-loading">Preparing {@instance_name}...</p>
    </div>
    """
  end

  defp renderer_context(instance_name, snapshot, pareidolia) do
    %{
      instanceName: instance_name,
      serverNow: DateTime.utc_now() |> DateTime.to_unix(:millisecond),
      contributions: snapshot.contributions,
      connections: snapshot.connections,
      pareidolia: pareidolia
    }
  end

  defp pareidolia_status("growing-mycelium-pareidolia", data_dir),
    do: Pareidolia.status(data_dir)

  defp pareidolia_status(_variant, _data_dir), do: nil

  defp schedule_refresh, do: Process.send_after(self(), :network_refresh, @refresh_interval)
end
