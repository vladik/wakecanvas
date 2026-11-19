defmodule WakeCanvas.Experience.CollectiveForm.SettingsLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    definition = WakeCanvas.Experience.CollectiveForm.definition()
    selected = get_in(session, ["config", "display_variant"])

    selected =
      if Enum.any?(definition.display_variants, &(&1.id == selected)),
        do: selected,
        else: definition.default_display_variant

    {:ok,
     assign(socket,
       page_title: "Collective Form Settings",
       instance_id: session["instance_id"],
       instance_reference: session["instance_reference"] || session["instance_id"],
       instance_name: session["instance_name"] || "Collective Form",
       stylesheet_url: session["experience_stylesheet_url"],
       config_api: session["config_api"],
       variants: definition.display_variants,
       selected_variant: selected,
       saved: false
     )}
  end

  @impl true
  def handle_event("select-variant", %{"variant" => variant_id}, socket) do
    if Enum.any?(socket.assigns.variants, &(&1.id == variant_id)) do
      {:noreply, assign(socket, selected_variant: variant_id, saved: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    patch = %{"display_variant" => socket.assigns.selected_variant}

    case socket.assigns.config_api.update_instance_config(socket.assigns.instance_id, patch) do
      {:ok, config} ->
        {:noreply,
         assign(socket,
           selected_variant: config["display_variant"] || socket.assigns.selected_variant,
           saved: true
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save settings: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link :if={@stylesheet_url} rel="stylesheet" href={@stylesheet_url} />
    <main class="cf-ui cf-settings">
      <div class="cf-settings__container">
        <a href="/manage" class="cf-settings__back">← Manage kiosk</a>
        <p class="cf-eyebrow">{@instance_name}</p>
        <h1>Presentation settings</h1>
        <p class="cf-lead">Choose the visual experience that opens on the projection. All variants share the same contributions and evolving network.</p>

        <div :if={@saved} class="cf-notice">Settings saved. Reopen the projection to load the selected variant.</div>

        <form phx-submit="save" class="cf-settings__form">
          <fieldset>
            <legend>Default projection</legend>
            <p>Selecting a variant changes its presentation only. It does not duplicate or modify the network.</p>

            <div class="cf-variant-grid">
              <label
                :for={variant <- @variants}
                class={["cf-variant-card", @selected_variant == variant.id && "is-selected"]}
              >
                <input
                  type="radio"
                  name="settings[display_variant]"
                  value={variant.id}
                  checked={@selected_variant == variant.id}
                  phx-click="select-variant"
                  phx-value-variant={variant.id}
                />
                <span>
                  <strong>{variant.label}</strong>
                  <small>{variant.description}</small>
                </span>
              </label>
            </div>
          </fieldset>

          <div class="cf-settings__actions">
            <a href={"/i/#{@instance_reference}/display/#{@selected_variant}"} target="_blank">Preview selected variant ↗</a>
            <button type="submit">Save settings</button>
          </div>
        </form>
      </div>
    </main>
    """
  end
end
