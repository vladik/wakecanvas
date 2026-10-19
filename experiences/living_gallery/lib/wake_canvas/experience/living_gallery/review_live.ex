defmodule WakeCanvas.Experience.LivingGallery.ReviewLive do
  use Phoenix.LiveView
  require Logger

  alias WakeCanvas.Experience.LivingGallery.Store

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:page_title, "Review Submissions")
      |> assign(:instance_id, session["instance_id"])
      |> assign(:instance_name, session["instance_name"])
      |> assign(:database_path, session["database_path"])
      |> assign(:data_dir, session["data_dir"])
      |> assign(:media_base_url, session["media_base_url"])
      |> assign(:pubsub_server, session["pubsub_server"])
      |> assign(:delete_candidate, nil)
      |> assign(:purge_candidate, nil)
      |> assign(:message_delete_candidate, nil)
      |> assign(:message_purge_candidate, nil)

    {:ok, load_items(socket)}
  end

  @impl true
  def handle_event("status", %{"id" => id, "status" => status}, socket) do
    :ok = Store.set_status(socket.assigns.database_path, String.to_integer(id), status)

    Phoenix.PubSub.broadcast(
      socket.assigns.pubsub_server,
      "living-gallery:#{socket.assigns.instance_id}",
      :media_changed
    )

    {:noreply, load_items(socket)}
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
         |> put_flash(:info, "Image and retained files were permanently deleted.")
         |> load_items()}

      {:error, :not_deleted} ->
        {:noreply,
         socket
         |> assign(:purge_candidate, nil)
         |> put_flash(:error, "Only a removed image can be permanently deleted.")
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

  @impl true
  def render(assigns) do
    ~H"""
    <main style="min-height:100vh;background:#f5f2ec;color:#29251f;font-family:ui-sans-serif,system-ui;padding:clamp(1.25rem,4vw,4rem)">
      <div style="max-width:1100px;margin:0 auto">
        <a href="/manage" style="color:#6c6255;text-decoration:none">← Manage kiosk</a>
        <h1 style="font:500 clamp(2.5rem,6vw,4.5rem)/1 Georgia,serif;margin:2rem 0 .5rem">Review Submissions</h1>
        <p style="color:#74695b">{@instance_name} · {Enum.count(@items, &(&1.status == "pending"))} awaiting review</p>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:1.2rem;margin-top:2rem">
          <article :for={item <- @items} style="overflow:hidden;border-radius:18px;background:white;box-shadow:0 12px 35px #4b382315">
            <img src={"#{@media_base_url}/#{item.filename}"} style="display:block;width:100%;aspect-ratio:4/3;object-fit:cover" />
            <div style="padding:1rem">
              <small style="text-transform:uppercase;letter-spacing:.12em;color:#8b5e3c">{String.replace(item.kind, "_", " ")}</small>
              <h2 style="margin:.35rem 0">{item.title || item.creator_name || "Untitled submission"}</h2>
              <p style="color:#756b5e">Status: {item.status}</p>
              <div style="display:flex;gap:.6rem;margin-top:1rem">
                <button :if={item.status != "published"} phx-click="status" phx-value-id={item.id} phx-value-status="published" style="flex:1;border:0;border-radius:9px;padding:.65rem;background:#2d6a4f;color:white;cursor:pointer">Publish</button>
                <button :if={item.status == "published"} phx-click="status" phx-value-id={item.id} phx-value-status="unpublished" style="flex:1;border:1px solid #c8b8ad;border-radius:9px;padding:.65rem;background:white;color:#8b3434;cursor:pointer">Unpublish</button>
              </div>
              <button phx-click="open_delete" phx-value-id={item.id} style="width:100%;margin-top:.65rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Remove image</button>
            </div>
          </article>
        </div>

        <section style="margin-top:3rem;border-top:1px solid #d8d0c4;padding-top:2rem">
          <h2 style="font:500 2rem Georgia,serif;margin:0">Messages and testimonials</h2>
          <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:1rem;margin-top:1rem">
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

        <section :if={@deleted_messages != []} style="margin-top:2rem">
          <h2 style="font:500 1.5rem Georgia,serif;margin:0">Removed messages</h2>
          <div style="display:grid;gap:.7rem;margin-top:1rem">
            <article :for={item <- @deleted_messages} style="padding:1rem;border-radius:12px;background:#e8e2d9">
              <span>“{item.body}”</span>
              <button phx-click="restore_message" phx-value-id={item.id} style="margin-left:1rem;border:1px solid #756b5e;border-radius:8px;padding:.4rem .7rem;background:white;cursor:pointer">Restore</button>
              <button phx-click="open_message_purge" phx-value-id={item.id} style="margin-left:.5rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Delete permanently</button>
            </article>
          </div>
        </section>

        <section :if={@deleted_items != []} style="margin-top:3rem;border-top:1px solid #d8d0c4;padding-top:2rem">
          <h2 style="font:500 2rem Georgia,serif;margin:0">Recently removed</h2>
          <p style="color:#74695b">Files are kept on this kiosk and can be restored.</p>
          <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:1rem;margin-top:1rem">
            <article :for={item <- @deleted_items} style="overflow:hidden;border-radius:14px;background:#e8e2d9">
              <img src={"#{@media_base_url}/#{item.filename}"} style="display:block;width:100%;aspect-ratio:4/3;object-fit:cover;opacity:.55" />
              <div style="padding:.8rem">
                <small>{String.replace(item.kind, "_", " ")}</small>
                <button phx-click="restore" phx-value-id={item.id} style="display:block;width:100%;margin-top:.6rem;border:1px solid #756b5e;border-radius:8px;padding:.5rem;background:white;cursor:pointer">Restore</button>
                <button phx-click="open_purge" phx-value-id={item.id} style="display:block;width:100%;margin-top:.5rem;border:0;background:transparent;color:#8b3434;text-decoration:underline;cursor:pointer">Delete permanently</button>
              </div>
            </article>
          </div>
        </section>
      </div>

      <dialog :if={@delete_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:32rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <h2 style="font:500 1.7rem Georgia,serif;margin:0">Remove this image?</h2>
          <p style="color:#74695b;line-height:1.5">It will disappear from the wall, but its file will remain safely stored and you can restore it from this page.</p>
          <div style="display:flex;justify-content:flex-end;gap:.7rem;margin-top:1.4rem">
            <button phx-click="cancel_delete" style="border:1px solid #c8b8ad;border-radius:9px;padding:.65rem 1rem;background:white;cursor:pointer">Cancel</button>
            <button phx-click="delete" phx-value-id={@delete_candidate.id} style="border:0;border-radius:9px;padding:.65rem 1rem;background:#8b3434;color:white;cursor:pointer">Remove image</button>
          </div>
        </div>
      </dialog>

      <dialog :if={@purge_candidate} open style="position:fixed;inset:0;margin:auto;border:0;border-radius:18px;padding:0;max-width:32rem;width:calc(100% - 2rem);box-shadow:0 30px 100px #0007">
        <div style="padding:1.5rem">
          <h2 style="font:500 1.7rem Georgia,serif;margin:0">Permanently delete this image?</h2>
          <p style="color:#74695b;line-height:1.5">This permanently removes the database record, prepared display image, and retained original. It cannot be restored.</p>
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
