defmodule WakeCanvas.Experience.CollectiveForm.ContributionLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.CollectiveForm.Store

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Add a Contribution",
       instance_id: session["instance_id"],
       instance_name: session["instance_name"] || "Collective Form",
       database_path: session["database_path"],
       pubsub_server: session["pubsub_server"],
       stylesheet_url: session["experience_stylesheet_url"],
       saved: false
     )}
  end

  @impl true
  def handle_event("save", %{"contribution" => attrs}, socket) do
    :ok = Store.add_contribution(socket.assigns.database_path, attrs)
    broadcast(socket)
    {:noreply, assign(socket, saved: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link :if={@stylesheet_url} rel="stylesheet" href={@stylesheet_url} />
    <main class="cf-ui">
      <section class="cf-panel cf-panel--narrow">
        <p class="cf-eyebrow">{@instance_name}</p>
        <h1>Add a contribution</h1>
        <p class="cf-lead">Create a digital node for a physical clay form. The operator will place it on the virtual table.</p>
        <div :if={@saved} class="cf-notice">Contribution added to the unplaced tray.</div>
        <form phx-submit="save" class="cf-form">
          <label>Optional title<input name="contribution[title]" maxlength="80" placeholder="Untitled form" /></label>
          <label>Node colour<input type="color" name="contribution[color]" value="#d8e7b0" /></label>
          <label>Approximate size
            <select name="contribution[size]">
              <option value="0.7">Small</option><option value="1.0" selected>Medium</option><option value="1.35">Large</option>
            </select>
          </label>
          <button type="submit">Add contribution</button>
        </form>
      </section>
    </main>
    """
  end

  defp broadcast(socket) do
    Phoenix.PubSub.broadcast(
      socket.assigns.pubsub_server,
      "collective-form:#{socket.assigns.instance_id}",
      :table_changed
    )
  end
end
