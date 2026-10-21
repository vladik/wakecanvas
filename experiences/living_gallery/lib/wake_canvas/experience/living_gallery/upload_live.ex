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
          instance_reference: session["instance_reference"] || session["instance_id"],
          instance_name: session["instance_name"],
          database_path: session["database_path"],
          data_dir: session["data_dir"],
          pubsub_server: session["pubsub_server"],
          stylesheet_url: session["experience_stylesheet_url"],
          auto_publish: Config.auto_publish?(session["config"], options.kind),
          retain_originals: Config.retain_originals?(session["config"]),
          saved: false
        })
      )
      |> Phoenix.LiveView.allow_upload(:image,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 12_000_000
      )
      |> Phoenix.LiveView.allow_upload(:original,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 12_000_000
      )

    {:ok, socket}
  end

  def save(params, socket) do
    metadata = params["submission"] || %{}
    media_dir = Path.join(socket.assigns.data_dir, "media")
    originals_dir = Path.join(socket.assigns.data_dir, "originals")
    File.mkdir_p!(media_dir)
    if socket.assigns.retain_originals, do: File.mkdir_p!(originals_dir)

    token = random_token()

    original = consume_original(socket, originals_dir, token)

    saved =
      Phoenix.LiveView.consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
        filename = "#{socket.assigns.kind}-#{token}#{safe_extension(entry.client_name)}"

        File.cp!(path, Path.join(media_dir, filename))

        Store.insert(socket.assigns.database_path, %{
          kind: socket.assigns.kind,
          status: if(socket.assigns.auto_publish, do: "published", else: "pending"),
          title: bounded_text(metadata["title"], 120),
          creator_name: bounded_text(metadata["creator_name"], 80),
          show_attribution: metadata["show_attribution"] == "true",
          filename: filename,
          mime_type: entry.client_type,
          original_filename: original && original.filename,
          original_mime_type: original && original.mime_type
        })

        {:ok, filename}
      end)

    if saved == [] and original,
      do: File.rm(Path.join(originals_dir, original.filename))

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
    <link rel="stylesheet" href={@stylesheet_url} />
    <main class="lg-ui lg-ui--intake" style="min-height:100vh;background:#f3efe7;color:#29251f;font-family:ui-sans-serif,system-ui;padding:clamp(1.25rem,4vw,4rem)">
      <div class="lg-ui__container" style="max-width:760px;margin:0 auto">
        <a href={"/i/#{@instance_reference}/display"} style="color:#6c6255;text-decoration:none">← Living Gallery</a>
        <p style="margin-top:3rem;text-transform:uppercase;letter-spacing:.18em;font-size:.72rem;color:#8b5e3c">{@instance_name}</p>
        <h1 style="font:500 clamp(2.5rem,7vw,5rem)/1 Georgia,serif;margin:.5rem 0 1rem">{@heading}</h1>
        <p style="max-width:580px;color:#6c6255;font-size:1.05rem;line-height:1.6">{@description}</p>
        <div :if={@saved && @auto_publish} class="lg-ui-notice lg-ui-notice--success" style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#dff3e5;color:#235934">Published. It is now appearing on the wall.</div>
        <div :if={@saved && !@auto_publish} class="lg-ui-notice lg-ui-notice--review" style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#f8edcf;color:#694f12">Uploaded for review. It will appear after an operator publishes it.</div>
        <form phx-change="validate" phx-submit="save" class="lg-ui-card lg-ui-form" style="margin-top:2rem;display:grid;gap:1rem;padding:clamp(1.2rem,4vw,2.2rem);border-radius:24px;background:#fff;box-shadow:0 18px 55px #4b382315">
          <div
            id={"media-input-#{@kind}"}
            phx-hook="ExperienceMediaInput"
            data-processor-url="/experience-assets/org.wakecanvas.experience.living-gallery/static/media/artwork-media.js"
            data-worker-url="/experience-assets/org.wakecanvas.experience.living-gallery/static/media/media-worker.js"
            data-retain-original={to_string(@retain_originals)}
            style="display:grid;gap:.8rem"
          >
            <label class="lg-ui-dropzone" style="display:grid;gap:.6rem;padding:2.2rem;border:2px dashed #c8bba9;border-radius:16px;background:#faf8f3;font-weight:600;text-align:center;cursor:pointer">
              Choose or take a photo
              <input data-media-source type="file" accept="image/jpeg,image/png,image/webp" capture="environment" style="width:100%" />
            </label>
            <.live_file_input upload={@uploads.image} style="display:none" />
            <.live_file_input upload={@uploads.original} style="display:none" />
            <div :if={@kind == "artwork"} style="display:flex;gap:1rem;align-items:center;flex-wrap:wrap">
              <label style="display:flex;gap:.5rem;align-items:center"><input data-remove-background type="checkbox" checked /> Remove controlled background</label>
              <label style="display:flex;gap:.5rem;align-items:center">Tolerance <input data-chroma-tolerance type="range" min="8" max="55" value="25" /></label>
            </div>
            <p data-media-status style="margin:0;color:#6c6255" aria-live="polite">The image will be resized on this device before upload.</p>
            <img data-media-preview hidden alt="Prepared upload preview" style="max-height:360px;max-width:100%;justify-self:center;object-fit:contain;border-radius:12px;background:#e8e2d8" />
          </div>
          <p :for={error <- upload_errors(@uploads.image)} style="color:#a52b2b">{Phoenix.Naming.humanize(error)}</p>
          <label style="display:grid;gap:.4rem;font-weight:600">Optional title<input name="submission[title]" maxlength="120" style="padding:.8rem 1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit" /></label>
          <label :if={@kind == "artwork"} style="display:grid;gap:.4rem;font-weight:600">Optional creator name<input name="submission[creator_name]" maxlength="80" style="padding:.8rem 1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit" /></label>
          <label :if={@kind == "artwork"} style="display:flex;gap:.65rem;align-items:center;color:#564e44"><input type="checkbox" name="submission[show_attribution]" value="true" /> Show the creator name on the wall</label>
          <button type="submit" style="border:0;border-radius:12px;padding:.9rem 1.2rem;background:#2d5d50;color:white;font-weight:700;font-size:1rem;cursor:pointer">{if @auto_publish, do: "Upload and publish", else: "Upload for review"}</button>
        </form>
      </div>
    </main>
    """
  end

  defp bounded_text(value, max) when is_binary(value),
    do: value |> String.trim() |> String.slice(0, max)

  defp bounded_text(_value, _max), do: nil

  defp consume_original(%{assigns: %{retain_originals: true}} = socket, directory, token) do
    Phoenix.LiveView.consume_uploaded_entries(socket, :original, fn %{path: path}, entry ->
      filename = "#{socket.assigns.kind}-#{token}-original#{safe_extension(entry.client_name)}"
      File.cp!(path, Path.join(directory, filename))
      {:ok, %{filename: filename, mime_type: entry.client_type}}
    end)
    |> List.first()
  end

  defp consume_original(socket, _directory, _token) do
    Phoenix.LiveView.consume_uploaded_entries(socket, :original, fn _meta, _entry ->
      {:ok, :discarded}
    end)

    nil
  end

  defp random_token,
    do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)

  defp safe_extension(filename) do
    case filename |> Path.extname() |> String.downcase() do
      extension when extension in [".jpg", ".jpeg", ".png", ".webp"] -> extension
      _extension -> ""
    end
  end
end
