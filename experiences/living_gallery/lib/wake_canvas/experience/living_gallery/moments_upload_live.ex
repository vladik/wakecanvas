defmodule WakeCanvas.Experience.LivingGallery.MomentsUploadLive do
  use Phoenix.LiveView
  alias WakeCanvas.Experience.LivingGallery.UploadLive

  def mount(_, session, socket),
    do:
      UploadLive.mount(session, socket, %{
        kind: "workshop_moment",
        heading: "Workshop Moments",
        description:
          "Share photographs as the workshop unfolds. Approved moments become the ambient moving collage."
      })

  def handle_event("validate", _, socket), do: {:noreply, socket}
  def handle_event("save", params, socket), do: UploadLive.save(params, socket)
  def render(assigns), do: UploadLive.render(assigns)
end
