defmodule WakeCanvas.Experience.LivingGallery.ArtworkIntakeLive do
  use Phoenix.LiveView
  alias WakeCanvas.Experience.LivingGallery.UploadLive

  def mount(_, session, socket),
    do:
      UploadLive.mount(session, socket, %{
        kind: "artwork",
        heading: "Add an Artwork",
        description:
          "Photograph a finished piece and send it to the projected gallery. Attribution is always optional."
      })

  def handle_event("validate", _, socket), do: {:noreply, socket}
  def handle_event("save", params, socket), do: UploadLive.save(params, socket)
  def render(assigns), do: UploadLive.render(assigns)
end
