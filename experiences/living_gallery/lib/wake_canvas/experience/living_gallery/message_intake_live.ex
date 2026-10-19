defmodule WakeCanvas.Experience.LivingGallery.MessageIntakeLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.LivingGallery.{Config, Store}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Share a Message",
       instance_id: session["instance_id"],
       instance_name: session["instance_name"],
       database_path: session["database_path"],
       pubsub_server: session["pubsub_server"],
       auto_publish: Config.auto_publish?(session["config"], "message"),
       saved: false
     )}
  end

  @impl true
  def handle_event("save", %{"message" => params}, socket) do
    body = params |> Map.get("body", "") |> String.trim() |> String.slice(0, 500)

    if body == "" do
      {:noreply, put_flash(socket, :error, "Write a message before sharing it.")}
    else
      :ok =
        Store.insert_message(socket.assigns.database_path, %{
          status: if(socket.assigns.auto_publish, do: "published", else: "pending"),
          body: body,
          author_name: bounded_text(params["author_name"], 80),
          show_attribution: params["show_attribution"] == "true"
        })

      Phoenix.PubSub.broadcast(
        socket.assigns.pubsub_server,
        "living-gallery:#{socket.assigns.instance_id}",
        :media_changed
      )

      {:noreply, assign(socket, :saved, true)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main style="min-height:100vh;background:#f3efe7;color:#29251f;font-family:ui-sans-serif,system-ui;padding:clamp(1.25rem,4vw,4rem)">
      <div style="max-width:700px;margin:0 auto">
        <a href={"/i/#{@instance_id}/display"} style="color:#6c6255;text-decoration:none">← Living Gallery</a>
        <p style="margin-top:3rem;text-transform:uppercase;letter-spacing:.18em;font-size:.72rem;color:#8b5e3c">{@instance_name}</p>
        <h1 style="font:500 clamp(2.5rem,7vw,5rem)/1 Georgia,serif;margin:.5rem 0 1rem">Share a message</h1>
        <p style="max-width:580px;color:#6c6255;font-size:1.05rem;line-height:1.6">Add a reflection, memory, or testimonial to the community tapestry.</p>
        <div :if={@saved && @auto_publish} style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#dff3e5;color:#235934">Shared. Your message is now part of the wall.</div>
        <div :if={@saved && !@auto_publish} style="margin-top:2rem;padding:1rem 1.2rem;border-radius:14px;background:#f8edcf;color:#694f12">Shared for review. It will appear after an operator publishes it.</div>
        <form phx-submit="save" style="margin-top:2rem;display:grid;gap:1rem;padding:clamp(1.2rem,4vw,2.2rem);border-radius:24px;background:white;box-shadow:0 18px 55px #4b382315">
          <label style="display:grid;gap:.4rem;font-weight:600">Your message<textarea name="message[body]" required maxlength="500" rows="6" style="resize:vertical;padding:1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit"></textarea></label>
          <label style="display:grid;gap:.4rem;font-weight:600">Optional name<input name="message[author_name]" maxlength="80" style="padding:.8rem 1rem;border:1px solid #d6cec2;border-radius:10px;font:inherit" /></label>
          <label style="display:flex;gap:.65rem;align-items:center;color:#564e44"><input type="checkbox" name="message[show_attribution]" value="true" /> Show my name on the wall</label>
          <button type="submit" style="border:0;border-radius:12px;padding:.9rem 1.2rem;background:#2d5d50;color:white;font-weight:700;font-size:1rem;cursor:pointer">{if @auto_publish, do: "Share on the wall", else: "Send for review"}</button>
        </form>
      </div>
    </main>
    """
  end

  defp bounded_text(value, max) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, max) do
      "" -> nil
      text -> text
    end
  end

  defp bounded_text(_value, _max), do: nil
end
