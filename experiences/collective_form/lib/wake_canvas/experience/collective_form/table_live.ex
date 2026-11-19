defmodule WakeCanvas.Experience.CollectiveForm.TableLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.CollectiveForm.{Pareidolia, Store}

  @columns 20
  @rows 12

  @impl true
  def mount(_params, session, socket) do
    topic = "collective-form:#{session["instance_id"]}"

    if connected?(socket) do
      Phoenix.PubSub.subscribe(session["pubsub_server"], topic)

      if get_in(session, ["config", "display_variant"]) == "growing-mycelium-pareidolia",
        do: schedule_pareidolia_refresh()
    end

    {:ok,
     socket
     |> assign(:page_title, "Table Console")
     |> assign(:instance_id, session["instance_id"])
     |> assign(:instance_reference, session["instance_reference"] || session["instance_id"])
     |> assign(:instance_name, session["instance_name"] || "Collective Form")
     |> assign(:database_path, session["database_path"])
     |> assign(:data_dir, session["data_dir"])
     |> assign(
       :display_variant,
       get_in(session, ["config", "display_variant"]) || "growing-mycelium"
     )
     |> assign(:pubsub_server, session["pubsub_server"])
     |> assign(:stylesheet_url, session["experience_stylesheet_url"])
     |> assign(:selected_id, nil)
     |> assign(:pareidolia_status, Pareidolia.status(session["data_dir"]))
     |> load_snapshot()}
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :selected_id, parse_id(id))}

  def handle_event(
        "place",
        %{"column" => column, "row" => row},
        %{assigns: %{selected_id: id}} = socket
      )
      when not is_nil(id) do
    x = (String.to_integer(column) + 0.5) / @columns
    y = (String.to_integer(row) + 0.5) / @rows
    :ok = Store.place_contribution(socket.assigns.database_path, id, x, y)
    broadcast(socket)
    {:noreply, load_snapshot(socket)}
  end

  def handle_event("place", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Select a contribution first.")}

  def handle_event("remove", %{"id" => id}, socket) do
    :ok = Store.remove_contribution(socket.assigns.database_path, parse_id(id))
    broadcast(socket)
    {:noreply, socket |> assign(:selected_id, nil) |> load_snapshot()}
  end

  def handle_event("unplace", %{"id" => id}, socket) do
    :ok = Store.unplace_contribution(socket.assigns.database_path, parse_id(id))
    broadcast(socket)
    {:noreply, socket |> assign(:selected_id, nil) |> load_snapshot()}
  end

  def handle_event("reset", _params, socket) do
    :ok = Store.reset_cycle(socket.assigns.database_path)
    broadcast(socket)
    {:noreply, socket |> assign(:selected_id, nil) |> load_snapshot()}
  end

  def handle_event("prepare-pareidolia", _params, socket) do
    case Pareidolia.prepare(socket.assigns.data_dir, socket.assigns.snapshot) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:pareidolia_status, Pareidolia.status(socket.assigns.data_dir))
         |> put_flash(
           :info,
           "Prepared #{result.candidate_count} candidates in #{result.directory}."
         )}

      {:error, :network_too_small} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Place enough connected contributions first (at least 3 connections)."
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not prepare interpretation: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:table_changed, socket), do: {:noreply, load_snapshot(socket)}

  def handle_info(:pareidolia_refresh, socket) do
    schedule_pareidolia_refresh()
    {:noreply, assign(socket, :pareidolia_status, Pareidolia.status(socket.assigns.data_dir))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link :if={@stylesheet_url} rel="stylesheet" href={@stylesheet_url} />
    <main class="cf-ui cf-console">
      <header class="cf-console__header">
        <div><p class="cf-eyebrow">{@instance_name}</p><h1>Table Console</h1><p class="cf-lead">Select a contribution, then choose its position on the table. Select it again to move it.</p></div>
        <div class="cf-actions"><a href={"/i/#{@instance_reference}/display"} target="_blank">Open projection ↗</a><button phx-click="reset" data-confirm="Start a new cycle and clear the current table?">Start new cycle</button></div>
      </header>
      <section :if={@display_variant == "growing-mycelium-pareidolia"} class="cf-pareidolia-panel">
        <div>
          <p class="cf-eyebrow">Pareidolia interpretation</p>
          <h2>Find forms in the current network</h2>
          <p>Create a local candidate sheet from real connections. During development, ask Codex to interpret the latest Pareidolia request; the projection picks up the validated response automatically.</p>
          <p class="cf-pareidolia-status">{pareidolia_status_text(@pareidolia_status)}</p>
        </div>
        <button phx-click="prepare-pareidolia">Prepare current network</button>
      </section>
      <div class="cf-console__body">
        <aside class="cf-tray">
          <h2>Contributions</h2>
          <p>{Enum.count(@snapshot.contributions, &(&1.state == "placed"))} placed · {Enum.count(@snapshot.contributions, &(&1.state == "unplaced"))} waiting</p>
          <div class="cf-contribution-list">
            <article :for={item <- Enum.reject(@snapshot.contributions, &(&1.state == "removed"))} class={["cf-contribution", @selected_id == item.id && "is-selected"]}>
              <button phx-click="select" phx-value-id={item.id} class="cf-contribution__select"><i style={"background:#{item.color};transform:scale(#{item.size})"}></i><span><strong>{display_title(item)}</strong><small>{if item.state == "placed", do: "Placed — select to move", else: "Waiting for placement"}</small></span></button>
              <div class="cf-contribution__actions">
                <button :if={item.state == "placed"} phx-click="unplace" phx-value-id={item.id} class="cf-contribution__unplace">Return to tray</button>
                <button :if={item.state == "unplaced"} phx-click="remove" phx-value-id={item.id} class="cf-contribution__remove" aria-label="Remove contribution" data-confirm="Remove this contribution from the current cycle?">×</button>
              </div>
            </article>
            <p :if={@snapshot.contributions == []} class="cf-empty">No contributions yet. Use “Add a Contribution” from the Experience menu.</p>
          </div>
        </aside>
        <section>
          <div class="cf-table" role="grid" aria-label="Virtual table">
            <button :for={{row, column} <- cells()} phx-click="place" phx-value-row={row} phx-value-column={column} aria-label={"Place at column #{column + 1}, row #{row + 1}"}></button>
            <i :for={item <- Enum.filter(@snapshot.contributions, &(&1.state == "placed"))} class={["cf-table-node", @selected_id == item.id && "is-selected"]} style={node_style(item)}></i>
          </div>
          <p class="cf-table-help">This normalized table represents the projection surface. Existing nodes remain visible after browser, Experience, platform, or computer restarts.</p>
        </section>
      </div>
    </main>
    """
  end

  defp load_snapshot(socket),
    do: assign(socket, :snapshot, Store.snapshot(socket.assigns.database_path))

  defp broadcast(socket),
    do:
      Phoenix.PubSub.broadcast(
        socket.assigns.pubsub_server,
        "collective-form:#{socket.assigns.instance_id}",
        :table_changed
      )

  defp parse_id(value) when is_integer(value), do: value
  defp parse_id(value), do: String.to_integer(value)
  defp display_title(%{title: title, id: id}) when title in [nil, ""], do: "Contribution #{id}"
  defp display_title(%{title: title}), do: title
  defp cells, do: for(row <- 0..(@rows - 1), column <- 0..(@columns - 1), do: {row, column})

  defp node_style(item),
    do:
      "left:#{item.x * 100}%;top:#{item.y * 100}%;background:#{item.color};transform:translate(-50%,-50%) scale(#{item.size})"

  defp pareidolia_status_text(%{status: "ready", interpretations: interpretations}),
    do: "Ready · #{length(interpretations)} interpretation(s) available on the projection."

  defp pareidolia_status_text(%{status: "awaiting_interpretation", candidateCount: count}),
    do: "Waiting for interpretation · #{count} candidates prepared."

  defp pareidolia_status_text(%{status: "invalid", error: error}),
    do: "The response needs attention: #{error}."

  defp pareidolia_status_text(_status),
    do: "No analysis package prepared for this instance yet."

  defp schedule_pareidolia_refresh,
    do: Process.send_after(self(), :pareidolia_refresh, 2_000)
end
