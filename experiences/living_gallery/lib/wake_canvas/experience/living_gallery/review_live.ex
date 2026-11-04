defmodule WakeCanvas.Experience.LivingGallery.ReviewLive do
  use Phoenix.LiveView
  require Logger

  alias WakeCanvas.Experience.LivingGallery.Store

  @refresh_interval 2_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        session["pubsub_server"],
        "living-gallery:#{session["instance_id"]}"
      )

      schedule_refresh()
    end

    socket =
      socket
      |> assign(:page_title, "Review Submissions")
      |> assign(:instance_id, session["instance_id"])
      |> assign(:instance_name, session["instance_name"])
      |> assign(:stylesheet_url, session["experience_stylesheet_url"])
      |> assign(:database_path, session["database_path"])
      |> assign(:data_dir, session["data_dir"])
      |> assign(:media_base_url, session["media_base_url"])
      |> assign(:pubsub_server, session["pubsub_server"])
      |> assign(:active_review_tab, "artwork")
      |> assign(:edit_candidate, nil)
      |> assign(:delete_candidate, nil)
      |> assign(:purge_candidate, nil)
      |> assign(:message_delete_candidate, nil)
      |> assign(:message_purge_candidate, nil)

    {:ok, load_items(socket)}
  end

  @impl true
  def handle_info(:media_changed, socket), do: {:noreply, load_items(socket)}

  def handle_info(:refresh_items, socket) do
    schedule_refresh()
    {:noreply, load_items(socket)}
  end

  @impl true
  def handle_event("select_review_tab", %{"tab" => tab}, socket)
      when tab in ["artwork", "moments", "messages", "removed"] do
    {:noreply, assign(socket, :active_review_tab, tab)}
  end

  def handle_event("status", %{"id" => id, "status" => status}, socket) do
    :ok = Store.set_status(socket.assigns.database_path, String.to_integer(id), status)

    Phoenix.PubSub.broadcast(
      socket.assigns.pubsub_server,
      "living-gallery:#{socket.assigns.instance_id}",
      :media_changed
    )

    {:noreply, load_items(socket)}
  end

  def handle_event("open_edit", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :edit_candidate, item)}
  end

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, :edit_candidate, nil)}

  def handle_event("save_metadata", %{"item_id" => id, "metadata" => params}, socket) do
    item_id = String.to_integer(id)

    :ok =
      Store.update_metadata(socket.assigns.database_path, item_id, %{
        title: bounded_text(params["title"], 120),
        creator_name: bounded_text(params["creator_name"], 80),
        show_attribution: params["show_attribution"] == "true"
      })

    if socket.assigns.edit_candidate.kind == "workshop_moment" do
      :ok =
        Store.set_featured(
          socket.assigns.database_path,
          item_id,
          params["featured"] == "true"
        )
    end

    broadcast_change(socket)

    {:noreply,
     socket
     |> assign(:edit_candidate, nil)
     |> put_flash(:info, "Submission details were updated.")
     |> load_items()}
  end

  def handle_event("open_delete", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.items, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :delete_candidate, item)}
  end

  def handle_event("cancel_delete", _params, socket),
    do: {:noreply, assign(socket, :delete_candidate, nil)}

  def handle_event("delete", %{"id" => id}, socket) do
    :ok = Store.soft_delete(socket.assigns.database_path, String.to_integer(id))
    broadcast_change(socket)
    {:noreply, socket |> assign(:delete_candidate, nil) |> load_items()}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    :ok = Store.restore(socket.assigns.database_path, String.to_integer(id))
    broadcast_change(socket)
    {:noreply, load_items(socket)}
  end

  def handle_event("open_purge", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.deleted_items, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :purge_candidate, item)}
  end

  def handle_event("cancel_purge", _params, socket),
    do: {:noreply, assign(socket, :purge_candidate, nil)}

  def handle_event("purge", %{"id" => id}, socket) do
    case Store.purge(socket.assigns.database_path, String.to_integer(id)) do
      {:ok, item} ->
        cleanup_files(socket, item)
        broadcast_change(socket)

        {:noreply,
         socket
         |> assign(:purge_candidate, nil)
         |> put_flash(:info, "Media and retained files were permanently deleted.")
         |> load_items()}

      {:error, :not_deleted} ->
        {:noreply,
         socket
         |> assign(:purge_candidate, nil)
         |> put_flash(:error, "Only removed media can be permanently deleted.")
         |> load_items()}
    end
  end

  def handle_event("message_status", %{"id" => id, "status" => status}, socket) do
    :ok = Store.set_message_status(socket.assigns.database_path, String.to_integer(id), status)
    broadcast_change(socket)
    {:noreply, load_items(socket)}
  end

  def handle_event("open_message_delete", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.messages, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :message_delete_candidate, item)}
  end

  def handle_event("cancel_message_delete", _params, socket),
    do: {:noreply, assign(socket, :message_delete_candidate, nil)}

  def handle_event("delete_message", %{"id" => id}, socket) do
    :ok = Store.soft_delete_message(socket.assigns.database_path, String.to_integer(id))
    broadcast_change(socket)
    {:noreply, socket |> assign(:message_delete_candidate, nil) |> load_items()}
  end

  def handle_event("restore_message", %{"id" => id}, socket) do
    :ok = Store.restore_message(socket.assigns.database_path, String.to_integer(id))
    broadcast_change(socket)
    {:noreply, load_items(socket)}
  end

  def handle_event("open_message_purge", %{"id" => id}, socket) do
    item = Enum.find(socket.assigns.deleted_messages, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :message_purge_candidate, item)}
  end

  def handle_event("cancel_message_purge", _params, socket),
    do: {:noreply, assign(socket, :message_purge_candidate, nil)}

  def handle_event("purge_message", %{"id" => id}, socket) do
    case Store.purge_message(socket.assigns.database_path, String.to_integer(id)) do
      :ok ->
        broadcast_change(socket)

        {:noreply,
         socket
         |> assign(:message_purge_candidate, nil)
         |> put_flash(:info, "Message was permanently deleted.")
         |> load_items()}

      {:error, :not_deleted} ->
        {:noreply,
         socket
         |> assign(:message_purge_candidate, nil)
         |> put_flash(:error, "Only a removed message can be permanently deleted.")
         |> load_items()}
    end
  end

  defp broadcast_change(socket) do
    Phoenix.PubSub.broadcast(
      socket.assigns.pubsub_server,
      "living-gallery:#{socket.assigns.instance_id}",
      :media_changed
    )
  end

  defp load_items(socket) do
    assign(socket,
      items: Store.list(socket.assigns.database_path),
      deleted_items: Store.list_deleted(socket.assigns.database_path),
      messages: Store.list_messages(socket.assigns.database_path),
      deleted_messages: Store.list_deleted_messages(socket.assigns.database_path)
    )
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh_items, @refresh_interval)

  defp cleanup_files(socket, item) do
    remove_file(Path.join(socket.assigns.data_dir, "media"), item.filename)
    remove_file(Path.join(socket.assigns.data_dir, "originals"), item.original_filename)
  end

  defp remove_file(_directory, nil), do: :ok

  defp remove_file(directory, filename) do
    if filename == Path.basename(filename) do
      case File.rm(Path.join(directory, filename)) do
        :ok ->
          :ok

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          Logger.warning("Could not remove purged Living Gallery file: #{inspect(reason)}")
      end
    end
  end

  defp bounded_text(value, max) when is_binary(value),
    do: value |> String.trim() |> String.slice(0, max)

  defp bounded_text(_value, _max), do: ""

  defp video?(item), do: String.starts_with?(item.mime_type || "", "video/")

  defp media_items_for_tab(items, "artwork"), do: Enum.filter(items, &(&1.kind == "artwork"))

  defp media_items_for_tab(items, "moments"),
    do: Enum.filter(items, &(&1.kind == "workshop_moment"))

  defp media_items_for_tab(_items, _tab), do: []

  defp media_label(item) do
    if video?(item), do: "Workshop video", else: String.replace(item.kind, "_", " ")
  end

  defp video_details(item) do
    duration =
      case item.duration_ms do
        milliseconds when is_integer(milliseconds) and milliseconds > 0 ->
          seconds = div(milliseconds, 1000)

          "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"

        _ ->
          "Unknown duration"
      end

    dimensions =
      if is_integer(item.width) and is_integer(item.height),
        do: "#{item.width}×#{item.height}",
        else: "Unknown dimensions"

    "#{duration} · #{dimensions}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href={@stylesheet_url} />
    <main class="lg-ui lg-ui--review" style="min-height:100vh;background:#f5f2ec;color:#29251f;font-family:ui-sans-serif,system-ui;padding:clamp(1.25rem,4vw,4rem)">
      <div class="lg-ui__container lg-ui__container--wide" style="max-width:1100px;margin:0 auto">
        <a href="/manage" style="color:#6c6255;text-decoration:none">← Manage kiosk</a>
        <h1 style="font:500 clamp(2.5rem,6vw,4.5rem)/1 Georgia,serif;margin:2rem 0 .5rem">Review Submissions</h1>
        <p style="color:#74695b">
          {@instance_name} · {Enum.count(@items, &(&1.status == "pending")) + Enum.count(@messages, &(&1.status == "pending"))} awaiting review
        </p>

        <nav class="lg-ui-review-tabs" role="tablist" aria-label="Review submission types">
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@active_review_tab == "artwork")}
            class={["lg-ui-review-tab", @active_review_tab == "artwork" && "lg-ui-review-tab--active"]}
            phx-click="select_review_tab"
            phx-value-tab="artwork"
          >
            <span class="lg-ui-review-tab__label">Artwork</span>
            <span class="lg-ui-review-tab__count">{Enum.count(@items, &(&1.kind == "artwork"))}</span>
            <small>Participant creations</small>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@active_review_tab == "moments")}
            class={["lg-ui-review-tab", @active_review_tab == "moments" && "lg-ui-review-tab--active"]}
            phx-click="select_review_tab"
            phx-value-tab="moments"
          >
            <span class="lg-ui-review-tab__label">Moments</span>
            <span class="lg-ui-review-tab__count">{Enum.count(@items, &(&1.kind == "workshop_moment"))}</span>
            <small>Workshop photos and videos</small>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@active_review_tab == "messages")}
            class={["lg-ui-review-tab", @active_review_tab == "messages" && "lg-ui-review-tab--active"]}
            phx-click="select_review_tab"
            phx-value-tab="messages"
          >
            <span class="lg-ui-review-tab__label">Messages</span>
            <span class="lg-ui-review-tab__count">{length(@messages)}</span>
            <small>Testimonials and reflections</small>
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={to_string(@active_review_tab == "removed")}
            class={["lg-ui-review-tab", @active_review_tab == "removed" && "lg-ui-review-tab--active"]}
            phx-click="select_review_tab"
            phx-value-tab="removed"
          >
            <span class="lg-ui-review-tab__label">Removed</span>
            <span class="lg-ui-review-tab__count">{length(@deleted_items) + length(@deleted_messages)}</span>
            <small>Restore or permanently delete</small>
          </button>
        </nav>

        <section :if={@active_review_tab in ["artwork", "moments"]} class="lg-ui-review-panel" role="tabpanel">
          <header class="lg-ui-review-panel__header">
            <h2>{if @active_review_tab == "artwork", do: "Artwork", else: "Workshop Moments"}</h2>
            <p>
              {if @active_review_tab == "artwork",
                do: "Review participant creations, creator details, and publishing status.",
                else: "Review workshop photos and videos, choose featured Moments, and control publishing."}
            </p>
          </header>
          <div :if={media_items_for_tab(@items, @active_review_tab) == []} class="lg-ui-review-empty">
            No submissions in this section yet.
          </div>
          <div :if={media_items_for_tab(@items, @active_review_tab) != []} class="lg-ui-review-grid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:1.2rem">
          <article :for={item <- media_items_for_tab(@items, @active_review_tab)} style="overflow:hidden;border-radius:18px;background:white;box-shadow:0 12px 35px #4b382315">
            <video
              :if={video?(item)}
              src={"#{@media_base_url}/#{item.filename}"}
              controls
              muted
              playsinline
              preload="metadata"
              style="display:block;width:100%;aspect-ratio:4/3;object-fit:contain;background:#08090c"
            >
            </video>
            <img :if={!video?(item)} src={"#{@media_base_url}/#{item.filename}"} style="display:block;width:100%;aspect-ratio:4/3;object-fit:cover" />
            <div style="padding:1rem">
              <small style="text-transform:uppercase;letter-spacing:.12em;color:#8b5e3c">
                {media_label(item)}
              </small>
              <h2 style="margin:.35rem 0">{item.title || item.creator_name || "Untitled submission"}</h2>
              <p :if={item.creator_name} style="margin:.2rem 0;color:#756b5e">
                Creator: {item.creator_name}
              </p>
              <p style="color:#756b5e">Status: {item.status}</p>
              <p :if={video?(item)} style="margin:.2rem 0;color:#756b5e;font-size:.85rem">
                {video_details(item)} · silent on the wall
              </p>
              <p :if={item.kind == "workshop_moment" && item.featured} style="margin:.55rem 0 0;color:#754b1c;font-size:.85rem;font-weight:650">
                Featured Moment
              </p>
              <div style="display:flex;gap:.6rem;margin-top:1rem">
                <button phx-click="open_edit" phx-value-id={item.id} style="flex:1;border:1px solid #2d5d50;border-radius:9px;padding:.65rem;background:white;color:#2d5d50;cursor:pointer">Edit details</button>
                <button :if={item.status != "published"} phx-click="status" phx-value-id={item.id} phx-value-status="published" style="flex:1;border:0;border-radius:9px;padding:.65rem;background:#2d6a4f;color:white;cursor:pointer">Publish</button>
                <button :if={item.status == "published"} phx-click="status" phx-value-id={item.id} phx-value-status="unpublished" style="flex:1;border:1px solid #c8b8ad;border-radius:9px;padding:.65rem;background:white;color:#8b3434;cursor:pointer">Unpublish</button>
              </div>
              <button phx-click="open_delete" phx-value-id={item.id} style="width:100%;margin-top:.65rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Remove media</button>
            </div>
          </article>
          </div>
        </section>

        <section :if={@active_review_tab == "messages"} class="lg-ui-review-panel lg-ui-review-section" role="tabpanel">
          <h2 style="font:500 2rem Georgia,serif;margin:0">Messages and testimonials</h2>
          <p style="color:#74695b">Review visitor reflections and control which messages appear on the wall.</p>
          <div :if={@messages == []} class="lg-ui-review-empty">No messages have been submitted yet.</div>
          <div :if={@messages != []} style="display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:1rem;margin-top:1rem">
            <article :for={item <- @messages} style="padding:1.2rem;border-radius:16px;background:white;box-shadow:0 12px 35px #4b382315">
              <blockquote style="margin:0;font:1.1rem/1.5 Georgia,serif">“{item.body}”</blockquote>
              <p :if={item.show_attribution && item.author_name} style="color:#756b5e">— {item.author_name}</p>
              <p style="color:#756b5e;font-size:.85rem">Status: {item.status}</p>
              <div style="display:flex;gap:.6rem;margin-top:1rem">
                <button :if={item.status != "published"} phx-click="message_status" phx-value-id={item.id} phx-value-status="published" style="flex:1;border:0;border-radius:9px;padding:.65rem;background:#2d6a4f;color:white;cursor:pointer">Publish</button>
                <button :if={item.status == "published"} phx-click="message_status" phx-value-id={item.id} phx-value-status="unpublished" style="flex:1;border:1px solid #c8b8ad;border-radius:9px;padding:.65rem;background:white;color:#8b3434;cursor:pointer">Unpublish</button>
              </div>
              <button phx-click="open_message_delete" phx-value-id={item.id} style="width:100%;margin-top:.65rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Remove message</button>
            </article>
          </div>
        </section>

        <section :if={@active_review_tab == "removed" && @deleted_messages != []} class="lg-ui-review-panel" role="tabpanel">
          <h2 style="font:500 1.5rem Georgia,serif;margin:0">Removed messages</h2>
          <div style="display:grid;gap:.7rem;margin-top:1rem">
            <article :for={item <- @deleted_messages} style="padding:1rem;border-radius:12px;background:#e8e2d9">
              <span>“{item.body}”</span>
              <button phx-click="restore_message" phx-value-id={item.id} style="margin-left:1rem;border:1px solid #756b5e;border-radius:8px;padding:.4rem .7rem;background:white;cursor:pointer">Restore</button>
              <button phx-click="open_message_purge" phx-value-id={item.id} style="margin-left:.5rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Delete permanently</button>
            </article>
          </div>
        </section>

        <section :if={@active_review_tab == "removed" && @deleted_items != []} class="lg-ui-review-panel" role="tabpanel">
          <h2 style="font:500 2rem Georgia,serif;margin:0">Recently removed</h2>
          <p style="color:#74695b">Files are kept on this kiosk and can be restored.</p>
          <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:1rem;margin-top:1rem">
            <article :for={item <- @deleted_items} style="overflow:hidden;border-radius:14px;background:#e8e2d9">
              <video
                :if={video?(item)}
                src={"#{@media_base_url}/#{item.filename}"}
                muted
                preload="metadata"
                style="display:block;width:100%;aspect-ratio:4/3;object-fit:contain;background:#08090c;opacity:.55"
              >
              </video>
              <img :if={!video?(item)} src={"#{@media_base_url}/#{item.filename}"} style="display:block;width:100%;aspect-ratio:4/3;object-fit:cover;opacity:.55" />
              <div style="padding:.8rem">
                <small>{String.replace(item.kind, "_", " ")}</small>
                <button phx-click="restore" phx-value-id={item.id} style="display:block;width:100%;margin-top:.6rem;border:1px solid #756b5e;border-radius:8px;padding:.5rem;background:white;cursor:pointer">Restore</button>
                <button phx-click="open_purge" phx-value-id={item.id} style="display:block;width:100%;margin-top:.5rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Delete permanently</button>
              </div>
            </article>
          </div>
        </section>

        <section
          :if={@active_review_tab == "removed" && @deleted_items == [] && @deleted_messages == []}
          class="lg-ui-review-panel"
          role="tabpanel"
        >
          <h2 style="font:500 2rem Georgia,serif;margin:0">Removed submissions</h2>
          <div class="lg-ui-review-empty">Nothing has been removed.</div>
        </section>
      </div>

      <dialog :if={@edit_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:36rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <p style="margin:0;text-transform:uppercase;letter-spacing:.14em;font-size:.7rem;color:#8b5e3c">
            {String.replace(@edit_candidate.kind, "_", " ")}
          </p>
          <h2 style="font:500 1.7rem Georgia,serif;margin:.35rem 0 0">Edit submission details</h2>
          <video
            :if={video?(@edit_candidate)}
            src={"#{@media_base_url}/#{@edit_candidate.filename}"}
            controls
            muted
            playsinline
            preload="metadata"
            style="display:block;width:100%;max-height:240px;margin-top:1rem;object-fit:contain;background:#08090c"
          >
          </video>
          <img
            :if={!video?(@edit_candidate)}
            src={"#{@media_base_url}/#{@edit_candidate.filename}"}
            alt="Submission preview"
            style="display:block;width:100%;max-height:240px;margin-top:1rem;border-radius:12px;object-fit:contain;background:#e8e2d9"
          />
          <form phx-submit="save_metadata" class="lg-ui-form" style="display:grid;gap:1rem;margin-top:1rem">
            <input type="hidden" name="item_id" value={@edit_candidate.id} />
            <label style="display:grid;gap:.4rem;font-weight:600">
              Title
              <input
                name="metadata[title]"
                value={@edit_candidate.title}
                maxlength="120"
                placeholder="Optional title"
              />
            </label>
            <label :if={@edit_candidate.kind == "artwork"} style="display:grid;gap:.4rem;font-weight:600">
              Creator name
              <input
                name="metadata[creator_name]"
                value={@edit_candidate.creator_name}
                maxlength="80"
                placeholder="Optional creator name"
              />
            </label>
            <label :if={@edit_candidate.kind == "artwork"} style="display:flex;align-items:flex-start;gap:.7rem;padding:.8rem;border:1px solid #ddd4c7;border-radius:12px;cursor:pointer">
              <input
                type="checkbox"
                name="metadata[show_attribution]"
                value="true"
                checked={@edit_candidate.show_attribution}
                style="width:1.2rem;height:1.2rem;margin-top:.1rem"
              />
              <span>
                <strong style="display:block">Show creator name on the wall</strong>
                <small style="display:block;margin-top:.25rem;color:#74695b;font-weight:400">
                  Variants that support attribution can display this name.
                </small>
              </span>
            </label>
            <label :if={@edit_candidate.kind == "workshop_moment"} style="display:flex;align-items:flex-start;gap:.7rem;padding:.9rem;border:1px solid #d7b889;border-radius:12px;background:#fffaf0;cursor:pointer">
              <input
                type="checkbox"
                name="metadata[featured]"
                value="true"
                checked={@edit_candidate.featured}
                style="width:1.2rem;height:1.2rem;margin-top:.1rem"
              />
              <span>
                <strong style="display:block">Mark as a featured Moment</strong>
                <small style="display:block;margin-top:.3rem;color:#74695b;font-weight:400;line-height:1.4">
                  Presentation variants may give featured Moments special emphasis.
                </small>
              </span>
            </label>
            <div style="display:flex;justify-content:flex-end;gap:.7rem;margin-top:.4rem">
              <button type="button" phx-click="cancel_edit" style="border:1px solid #c8b8ad;border-radius:9px;padding:.65rem 1rem;background:white;cursor:pointer">Cancel</button>
              <button type="submit">Save details</button>
            </div>
          </form>
        </div>
      </dialog>

      <dialog :if={@delete_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:32rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <h2 style="font:500 1.7rem Georgia,serif;margin:0">Remove this media?</h2>
          <p style="color:#74695b;line-height:1.5">It will disappear from the wall, but its file will remain safely stored and you can restore it from this page.</p>
          <div style="display:flex;justify-content:flex-end;gap:.7rem;margin-top:1.4rem">
            <button phx-click="cancel_delete" style="border:1px solid #c8b8ad;border-radius:9px;padding:.65rem 1rem;background:white;cursor:pointer">Cancel</button>
            <button phx-click="delete" phx-value-id={@delete_candidate.id} style="border:0;border-radius:9px;padding:.65rem 1rem;background:#8b3434;color:white;cursor:pointer">Remove media</button>
          </div>
        </div>
      </dialog>

      <dialog :if={@purge_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:32rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <h2 style="font:500 1.7rem Georgia,serif;margin:0">Permanently delete this media?</h2>
          <p style="color:#74695b;line-height:1.5">This permanently removes the database record, display file, and any retained original. It cannot be restored.</p>
          <div style="display:flex;justify-content:flex-end;gap:.7rem;margin-top:1.4rem">
            <button phx-click="cancel_purge" style="border:1px solid #c8b8ad;border-radius:9px;padding:.65rem 1rem;background:white;cursor:pointer">Cancel</button>
            <button phx-click="purge" phx-value-id={@purge_candidate.id} style="border:0;border-radius:9px;padding:.65rem 1rem;background:#8b3434;color:white;cursor:pointer">Delete permanently</button>
          </div>
        </div>
      </dialog>

      <dialog :if={@message_delete_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:32rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <h2 style="font:500 1.7rem Georgia,serif;margin:0">Remove this message?</h2>
          <p style="color:#74695b;line-height:1.5">It will disappear from the wall but remain recoverable.</p>
          <div style="display:flex;justify-content:flex-end;gap:.7rem;margin-top:1.4rem">
            <button phx-click="cancel_message_delete" style="border:1px solid #c8b8ad;border-radius:9px;padding:.65rem 1rem;background:white;cursor:pointer">Cancel</button>
            <button phx-click="delete_message" phx-value-id={@message_delete_candidate.id} style="border:0;border-radius:9px;padding:.65rem 1rem;background:#8b3434;color:white;cursor:pointer">Remove message</button>
          </div>
        </div>
      </dialog>

      <dialog :if={@message_purge_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:32rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <h2 style="font:500 1.7rem Georgia,serif;margin:0">Permanently delete this message?</h2>
          <p style="color:#74695b;line-height:1.5">This cannot be restored.</p>
          <div style="display:flex;justify-content:flex-end;gap:.7rem;margin-top:1.4rem">
            <button phx-click="cancel_message_purge" style="border:1px solid #c8b8ad;border-radius:9px;padding:.65rem 1rem;background:white;cursor:pointer">Cancel</button>
            <button phx-click="purge_message" phx-value-id={@message_purge_candidate.id} style="border:0;border-radius:9px;padding:.65rem 1rem;background:#8b3434;color:white;cursor:pointer">Delete permanently</button>
          </div>
        </div>
      </dialog>
    </main>
    """
  end
end
