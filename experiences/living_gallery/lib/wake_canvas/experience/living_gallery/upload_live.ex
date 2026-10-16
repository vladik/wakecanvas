defmodule WakeCanvas.Experience.LivingGallery.UploadLive do
  use Phoenix.Component
  alias WakeCanvas.Experience.LivingGallery.{Config, Store}

  def mount(session, socket, options) do
    socket =
      socket
      |> assign(
        Map.merge(options, %{
          page_title: options.heading,
          instance_id: session["instance_id"],
          instance_name: session["instance_name"],
          database_path: session["database_path"],
          data_dir: session["data_dir"],
          pubsub_server: session["pubsub_server"],
          auto_publish: Config.auto_publish?(session["config"], options.kind),
          saved: false
        })
      )
      |> Phoenix.LiveView.allow_upload(:image,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 12_000_000
      )

    {:ok, socket}
  end

  def save(params, socket) do
    metadata = params["submission"] || %{}
    media_dir = Path.join(socket.assigns.data_dir, "media")
    File.mkdir_p!(media_dir)

    saved =
      Phoenix.LiveView.consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        filename =
          "#{socket.assigns.kind}-#{System.unique_integer([:positive])}#{Path.extname(entry.client_name) |> String.downcase()}"

        File.cp!(path, Path.join(media_dir, filename))

        Store.insert(socket.assigns.database_path, %{
          kind: socket.assigns.kind,
          status: if(socket.assigns.auto_publish, do: "published", else: "pending"),
          title: metadata["title"],
          creator_name: metadata["creator_name"],
          show_attribution: metadata["show_attribution"] == "true",
          filename: filename,
          mime_type: entry.client_type
        })

        {:ok, filename}
      end)

    if saved != [],
      do:
        Phoenix.PubSub.broadcast(
          socket.assigns.pubsub_server,
          "living-gallery:#{socket.assigns.instance_id}",
          :media_changed
        )

    {:noreply, assign(socket, :saved, saved != [])}
  end

  def render(assigns) do
    ~H"""
    <main style="min-height:100vh;background:#f3efe7;color:#29251f;font-family:ui-sans-serif,system-ui;padding:clamp(1.25rem,4vw,4rem)">
      <div style="max-width:760px;margin:0 auto">
        <a href={"/i/#{@instance_id}/display"} style="color:#6c6255;text-decoration:none">← Living Gallery</a>
        <p style="margin-top:3rem;text-transform:uppercase;letter-spacing:.18em;font-size:.72rem;color:#8b5e3c">{@instance_name}</p>
        <h1 style="font:500 clamp(2.5rem,7vw,5rem)/1 Georgia,serif;margin:.5rem 0 1rem">{@heading}</h1>
        <p style="max-width:580px;color:#6c6255;font-size:1.05rem;line-height:1.6">{@description}</p>
        <div :if={@saved && @auto_publish} style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#dff3e5;color:#235934">Published. It is now appearing on the wall.</div>
        <div :if={@saved && !@auto_publish} style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#f8edcf;color:#694f12">Uploaded for review. It will appear after an operator publishes it.</div>
        <form phx-change="validate" phx-submit="save" style="margin-top:2rem;display:grid;gap:1rem;padding:clamp(1.2rem,4vw,2.2rem);border-radius:24px;background:#fff;box-shadow:0 18px 55px #4b382315">
          <.live_file_input upload={@uploads.image} style="width:100%;padding:2.2rem;border:2px dashed #c8bba9;border-radius:16px;background:#faf8f3" />
          <p :for={error <- upload_errors(@uploads.image)} style="color:#a52b2b">{Phoenix.Naming.humanize(error)}</p>
          <label style="display:grid;gap:.4rem;font-weight:600">Optional title<input name="submission[title]" style="padding:.8rem 1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit" /></label>
          <label :if={@kind == "artwork"} style="display:grid;gap:.4rem;font-weight:600">Optional creator name<input name="submission[creator_name]" style="padding:.8rem 1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit" /></label>
          <label :if={@kind == "artwork"} style="display:flex;gap:.65rem;align-items:center;color:#564e44"><input type="checkbox" name="submission[show_attribution]" value="true" /> Show the creator name on the wall</label>
          <button type="submit" style="border:0;border-radius:12px;padding:.9rem 1.2rem;background:#2d5d50;color:white;font-weight:700;font-size:1rem;cursor:pointer">{if @auto_publish, do: "Upload and publish", else: "Upload for review"}</button>
        </form>
      </div>
    </main>
    """
  end
end
