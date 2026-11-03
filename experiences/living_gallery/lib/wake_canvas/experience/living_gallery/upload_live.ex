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
          media_type: "photo",
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

    socket = maybe_allow_video(socket, options.kind)

    {:ok, socket}
  end

  def save(params, socket) do
    metadata = params["submission"] || %{}
    video_metadata = params["video"] || %{}
    media_dir = Path.join(socket.assigns.data_dir, "media")
    originals_dir = Path.join(socket.assigns.data_dir, "originals")
    File.mkdir_p!(media_dir)
    if socket.assigns.retain_originals, do: File.mkdir_p!(originals_dir)

    token = random_token()

    original = consume_original(socket, originals_dir, token)

    saved_images =
      if socket.assigns.kind != "workshop_moment" || socket.assigns.media_type == "photo" do
        Phoenix.LiveView.consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
          filename = "#{socket.assigns.kind}-#{token}#{safe_extension(entry.client_name)}"

          File.cp!(path, Path.join(media_dir, filename))

          Store.insert(socket.assigns.database_path, %{
            kind: socket.assigns.kind,
            status: if(socket.assigns.auto_publish, do: "published", else: "pending"),
            title: bounded_text(metadata["title"], 120),
            creator_name: bounded_text(metadata["creator_name"], 80),
            show_attribution: metadata["show_attribution"] == "true",
            featured: socket.assigns.kind == "workshop_moment" && metadata["featured"] == "true",
            filename: filename,
            mime_type: entry.client_type,
            original_filename: original && original.filename,
            original_mime_type: original && original.mime_type
          })

          {:ok, filename}
        end)
      else
        []
      end

    saved_videos = consume_videos(socket, media_dir, token, metadata, video_metadata)
    saved = saved_images ++ saved_videos

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

  def select_media_type(type, socket) when type in ["photo", "video"] do
    socket =
      case type do
        "photo" -> cancel_entries(socket, :video)
        "video" -> socket |> cancel_entries(:image) |> cancel_entries(:original)
      end

    {:noreply, assign(socket, media_type: type, saved: false)}
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
          <div :if={@kind == "workshop_moment"} class="lg-ui-media-tabs" role="tablist" aria-label="Choose Moment media type">
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@media_type == "photo")}
              class={if(@media_type == "photo", do: "lg-ui-media-tab lg-ui-media-tab--active", else: "lg-ui-media-tab")}
              phx-click="select_media_type"
              phx-value-type="photo"
            >
              <span class="lg-ui-media-tab__indicator" aria-hidden="true"></span>
              <span class="lg-ui-media-tab__copy">
                <strong>Photo</strong>
                <small>JPG, PNG or WebP</small>
              </span>
              <span :if={@media_type == "photo"} class="lg-ui-media-tab__selected">Selected</span>
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@media_type == "video")}
              class={if(@media_type == "video", do: "lg-ui-media-tab lg-ui-media-tab--active", else: "lg-ui-media-tab")}
              phx-click="select_media_type"
              phx-value-type="video"
            >
              <span class="lg-ui-media-tab__indicator" aria-hidden="true"></span>
              <span class="lg-ui-media-tab__copy">
                <strong>Video</strong>
                <small>MP4 or WebM</small>
              </span>
              <span :if={@media_type == "video"} class="lg-ui-media-tab__selected">Selected</span>
            </button>
          </div>
          <div
            :if={@kind != "workshop_moment" || @media_type == "photo"}
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
          <div
            :if={@kind == "workshop_moment" && @media_type == "video"}
            id="workshop-video-input"
            phx-hook="ExperienceVideoInput"
            style="display:grid;gap:.8rem"
          >
            <label class="lg-ui-dropzone" style="display:grid;gap:.6rem;padding:2.2rem;border:2px dashed #c8bba9;border-radius:16px;background:#faf8f3;font-weight:600;text-align:center;cursor:pointer">
              Choose a video
              <.live_file_input
                upload={@uploads.video}
                data-video-source
                accept="video/mp4,video/webm"
                style="width:100%"
              />
            </label>
            <p data-video-status style="margin:0;color:#6c6255" aria-live="polite">
              MP4 or WebM, stored only in this workshop. The kiosk will check compatibility, orientation, and duration. Playback is always silent.
            </p>
            <video
              data-video-preview
              hidden
              controls
              muted
              playsinline
              style="display:block;max-height:360px;max-width:100%;justify-self:center;background:#08090c"
            >
            </video>
            <input data-video-duration type="hidden" name="video[duration_ms]" />
            <input data-video-width type="hidden" name="video[width]" />
            <input data-video-height type="hidden" name="video[height]" />
            <input data-video-size type="hidden" name="video[file_size]" />
            <p :for={error <- upload_errors(@uploads.video)} style="color:#a52b2b">
              {Phoenix.Naming.humanize(error)}
            </p>
          </div>
          <label style="display:grid;gap:.4rem;font-weight:600">Optional title<input name="submission[title]" maxlength="120" style="padding:.8rem 1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit" /></label>
          <label :if={@kind == "workshop_moment"} style="display:flex;align-items:flex-start;gap:.7rem;padding:.9rem;border:1px solid #d7b889;border-radius:12px;background:#fffaf0;cursor:pointer">
            <input type="checkbox" name="submission[featured]" value="true" style="width:1.2rem;height:1.2rem;margin-top:.1rem" />
            <span>
              <strong style="display:block">Mark as a featured Moment</strong>
              <small style="display:block;margin-top:.3rem;color:#74695b;font-weight:400;line-height:1.4">
                Presentation variants may give featured Moments special emphasis. You can change this later under Review.
              </small>
            </span>
          </label>
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

  defp maybe_allow_video(socket, "workshop_moment") do
    Phoenix.LiveView.allow_upload(socket, :video,
      accept: ~w(.mp4 .webm),
      max_entries: 1,
      max_file_size: 500_000_000
    )
  end

  defp maybe_allow_video(socket, _kind), do: socket

  defp consume_videos(
         %{assigns: %{kind: "workshop_moment", media_type: "video"}} = socket,
         directory,
         token,
         metadata,
         video_metadata
       ) do
    Phoenix.LiveView.consume_uploaded_entries(socket, :video, fn %{path: path}, entry ->
      filename = "workshop_moment-#{token}#{safe_video_extension(entry.client_name)}"
      File.cp!(path, Path.join(directory, filename))

      Store.insert(socket.assigns.database_path, %{
        kind: "workshop_moment",
        status: if(socket.assigns.auto_publish, do: "published", else: "pending"),
        title: bounded_text(metadata["title"], 120),
        creator_name: nil,
        show_attribution: false,
        filename: filename,
        mime_type: video_mime_type(entry),
        featured: metadata["featured"] == "true",
        duration_ms: positive_integer(video_metadata["duration_ms"]),
        width: positive_integer(video_metadata["width"]),
        height: positive_integer(video_metadata["height"]),
        file_size: positive_integer(video_metadata["file_size"]) || entry.client_size
      })

      {:ok, filename}
    end)
  end

  defp consume_videos(_socket, _directory, _token, _metadata, _video_metadata), do: []

  defp safe_video_extension(filename) do
    case filename |> Path.extname() |> String.downcase() do
      extension when extension in [".mp4", ".webm"] -> extension
      _extension -> ""
    end
  end

  defp video_mime_type(entry) do
    if String.starts_with?(entry.client_type || "", "video/") do
      entry.client_type
    else
      case safe_video_extension(entry.client_name) do
        ".webm" -> "video/webm"
        _ -> "video/mp4"
      end
    end
  end

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil

  defp cancel_entries(socket, upload_name) do
    Enum.reduce(socket.assigns.uploads[upload_name].entries, socket, fn entry, acc ->
      Phoenix.LiveView.cancel_upload(acc, upload_name, entry.ref)
    end)
  end
end
