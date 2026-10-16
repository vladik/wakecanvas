defmodule WakeCanvas.Experience.LivingGallery.SettingsLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.LivingGallery.Config

  @impl true
  def mount(_params, session, socket) do
    definition = WakeCanvas.Experience.LivingGallery.definition()

    {:ok,
     assign(socket,
       page_title: "Living Gallery Settings",
       instance_id: session["instance_id"],
       instance_name: session["instance_name"],
       config_api: session["config_api"],
       config: Config.with_defaults(session["config"]),
       variants: definition.display_variants,
       selected_variant: Config.with_defaults(session["config"])["display_variant"],
       saved: false
     )}
  end

  @impl true
  def handle_event("select_variant", %{"variant" => variant_id}, socket) do
    if Enum.any?(socket.assigns.variants, &(&1.id == variant_id)) do
      {:noreply, assign(socket, selected_variant: variant_id, saved: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", params, socket) do
    settings = params["settings"] || %{}

    patch = %{
      "artwork_auto_publish" => settings["artwork_auto_publish"] == "true",
      "moments_auto_publish" => settings["moments_auto_publish"] == "true",
      "display_variant" => socket.assigns.selected_variant
    }

    case socket.assigns.config_api.update_instance_config(socket.assigns.instance_id, patch) do
      {:ok, config} ->
        config = Config.with_defaults(config)

        {:noreply,
         assign(socket, config: config, selected_variant: config["display_variant"], saved: true)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save settings: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main style="min-height:100vh;background:#f3efe7;color:#29251f;font-family:ui-sans-serif,system-ui;padding:clamp(1.25rem,4vw,4rem)">
      <div style="max-width:760px;margin:0 auto">
        <a href="/manage" style="color:#6c6255;text-decoration:none">← Manage kiosk</a>
        <p style="margin-top:3rem;text-transform:uppercase;letter-spacing:.18em;font-size:.72rem;color:#8b5e3c">{@instance_name}</p>
        <h1 style="font:500 clamp(2.5rem,7vw,5rem)/1 Georgia,serif;margin:.5rem 0 1rem">Publishing settings</h1>
        <p style="max-width:620px;color:#6c6255;font-size:1.05rem;line-height:1.6">Choose whether new uploads appear immediately or wait for an operator to publish them.</p>

        <div :if={@saved} style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#dff3e5;color:#235934">Settings saved.</div>

        <form phx-submit="save" style="margin-top:2rem;display:grid;gap:1rem;padding:clamp(1.2rem,4vw,2.2rem);border-radius:24px;background:#fff;box-shadow:0 18px 55px #4b382315">
          <fieldset style="border:0;padding:0;margin:0 0 1rem">
            <legend style="font:600 1.3rem Georgia,serif;margin-bottom:.35rem">Default wall presentation</legend>
            <p style="margin:.2rem 0 1rem;color:#74695b">This variant opens automatically after the kiosk restarts.</p>
            <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:1rem">
              <div :for={variant <- @variants} style={["display:grid;gap:.8rem;padding:.8rem;border:2px solid;border-radius:16px", if(@selected_variant == variant.id, do: "border-color:#2d5d50;background:#f0f6f2", else: "border-color:#ddd4c7;background:white")]}>
                <div style={["height:120px;border-radius:11px;position:relative;overflow:hidden", if(variant.id == "living-collage", do: "background:radial-gradient(circle at 20% 25%,#735f44,transparent 35%),#1c211e", else: "background:radial-gradient(circle at 50% 45%,#6d5940,transparent 28%),#111210")]}>
                  <span :if={variant.id == "living-collage"} style="position:absolute;left:12%;top:20%;width:34%;height:45%;background:#d9cdb9;transform:rotate(-6deg);box-shadow:45px 30px 0 #a89a84"></span>
                  <span style={["position:absolute;background:#f8f3e8;box-shadow:0 8px 24px #0008", if(variant.id == "living-collage", do: "left:42%;top:25%;width:42%;height:58%;transform:rotate(2deg)", else: "left:31%;top:14%;width:38%;height:70%")]}></span>
                </div>
                <label style="display:flex;align-items:flex-start;gap:.7rem;cursor:pointer">
                  <input type="radio" name="settings[display_variant]" value={variant.id} checked={@selected_variant == variant.id} phx-click="select_variant" phx-value-variant={variant.id} style="margin-top:.25rem" />
                  <span><strong style="display:block">{variant.label}</strong><small style="display:block;margin-top:.25rem;color:#74695b;line-height:1.4">{variant.description}</small></span>
                </label>
                <a href={"/i/#{@instance_id}/display?variant=#{variant.id}"} target="_blank" style="justify-self:start;color:#2d5d50;font-weight:600">Preview variant ↗</a>
              </div>
            </div>
            <div style="display:flex;align-items:center;justify-content:space-between;gap:1rem;flex-wrap:wrap;margin-top:1rem">
              <small style="color:#74695b">Previewing does not change what starts after reboot.</small>
              <a href={"/i/#{@instance_id}/display?variant=#{@selected_variant}"} target="_blank" style="display:inline-block;border:1px solid #2d5d50;border-radius:10px;padding:.65rem 1rem;color:#2d5d50;font-weight:700;text-decoration:none">Preview selected variant ↗</a>
            </div>
          </fieldset>

          <label style="display:flex;align-items:flex-start;gap:1rem;padding:1rem;border:1px solid #ddd4c7;border-radius:14px;cursor:pointer">
            <input type="checkbox" name="settings[artwork_auto_publish]" value="true" checked={@config["artwork_auto_publish"]} style="width:1.3rem;height:1.3rem;margin-top:.15rem" />
            <span><strong style="display:block">Automatically publish artwork</strong><small style="display:block;margin-top:.35rem;color:#74695b;line-height:1.45">Participant artwork appears on the wall immediately after upload.</small></span>
          </label>

          <label style="display:flex;align-items:flex-start;gap:1rem;padding:1rem;border:1px solid #ddd4c7;border-radius:14px;cursor:pointer">
            <input type="checkbox" name="settings[moments_auto_publish]" value="true" checked={@config["moments_auto_publish"]} style="width:1.3rem;height:1.3rem;margin-top:.15rem" />
            <span><strong style="display:block">Automatically publish Workshop Moments</strong><small style="display:block;margin-top:.35rem;color:#74695b;line-height:1.45">Workshop photographs appear immediately instead of waiting for review.</small></span>
          </label>

          <button type="submit" style="justify-self:end;border:0;border-radius:12px;padding:.9rem 1.4rem;background:#2d5d50;color:white;font-weight:700;font-size:1rem;cursor:pointer">Save settings</button>
        </form>
      </div>
    </main>
    """
  end
end
