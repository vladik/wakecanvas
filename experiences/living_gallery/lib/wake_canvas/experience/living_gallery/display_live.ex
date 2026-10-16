defmodule WakeCanvas.Experience.LivingGallery.DisplayLive do
  use Phoenix.LiveView

  alias WakeCanvas.Experience.LivingGallery.Store
  alias WakeCanvas.Experience.LivingGallery.Variants.QuietSpotlight

  @impl true
  def mount(_params, session, socket) do
    topic = "living-gallery:#{session["instance_id"]}"
    if connected?(socket), do: Phoenix.PubSub.subscribe(session["pubsub_server"], topic)

    {:ok,
     socket
     |> assign(:page_title, session["instance_name"] || "Living Gallery")
     |> assign(:instance_id, session["instance_id"])
     |> assign(:instance_name, session["instance_name"] || "Living Gallery")
     |> assign(:display_variant, session["display_variant"] || "living-collage")
     |> assign(:database_path, session["database_path"])
     |> assign(:media_base_url, session["media_base_url"])
     |> load_items()}
  end

  @impl true
  def handle_info(:media_changed, socket), do: {:noreply, load_items(socket)}

  defp load_items(socket) do
    items = Store.list(socket.assigns.database_path, "published")

    assign(socket,
      moments: Enum.filter(items, &(&1.kind == "workshop_moment")) |> Enum.take(6),
      artworks: Enum.filter(items, &(&1.kind == "artwork"))
    )
  end

  @impl true
  def render(%{display_variant: "quiet-spotlight"} = assigns),
    do: QuietSpotlight.render(assigns)

  def render(assigns) do
    ~H"""
    <div class="lg-wall" data-wakecanvas-experience="living-gallery">
      <style>
        body { margin: 0; overflow: hidden; background: #161512; }
        .lg-wall { position: relative; min-height: 100vh; overflow: hidden; color: #fffaf0; font-family: ui-sans-serif, system-ui, sans-serif; background: radial-gradient(circle at 20% 20%, #514331 0, transparent 32%), radial-gradient(circle at 82% 72%, #303d38 0, transparent 36%), #171612; }
        .lg-grain { position: absolute; inset: 0; opacity: .14; background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 180 180' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='.35'/%3E%3C/svg%3E"); }
        .lg-title { position: absolute; top: 4vh; left: 4vw; z-index: 10; letter-spacing: .18em; text-transform: uppercase; font-size: clamp(.72rem, 1vw, 1rem); opacity: .7; }
        .lg-title strong { display: block; margin-top: .45rem; letter-spacing: -.04em; text-transform: none; font-family: Georgia, serif; font-size: clamp(2rem, 4vw, 5rem); font-weight: 500; opacity: 1; }
        .lg-moment { position: absolute; width: clamp(150px, 20vw, 360px); aspect-ratio: 4/3; padding: 10px 10px 42px; border-radius: 3px; background: #e8dfce; box-shadow: 0 22px 70px #0009; animation: lg-drift 13s ease-in-out infinite alternate; }
        .lg-moment::before { content: ""; display: block; width: 100%; height: 100%; background: linear-gradient(145deg, var(--a), var(--b)); filter: saturate(.65); }
        .lg-moment:has(img)::before { display:none; }
        .lg-moment::after { content: attr(data-label); position: absolute; left: 14px; bottom: 13px; color: #39342d; font: 600 .68rem ui-sans-serif, system-ui; letter-spacing: .12em; text-transform: uppercase; }
        .lg-m1 { left: 7%; top: 28%; --a:#9b6b4f; --b:#283e3b; transform: rotate(-5deg); }
        .lg-m2 { right: 8%; top: 8%; --a:#6e7f6b; --b:#ae7955; transform: rotate(4deg); animation-delay:-4s; }
        .lg-m3 { right: 15%; bottom: 7%; --a:#604f75; --b:#bb8a58; transform: rotate(-3deg); animation-delay:-8s; }
        .lg-art { position: absolute; z-index: 5; left: 50%; top: 54%; width: clamp(220px, 29vw, 520px); aspect-ratio: 4/3; padding: clamp(10px, 1.2vw, 22px); transform: translate(-50%, -50%) rotate(.8deg); background: #fffdf6; box-shadow: 0 35px 100px #000c, 0 0 0 1px #fff8; animation: lg-breathe 6s ease-in-out infinite; }
        .lg-art-image { width: 100%; height: 100%; background: radial-gradient(circle at 48% 42%, #f8cd68 0 9%, transparent 10%), conic-gradient(from 20deg at 50% 50%, #ef665c, #efb953, #4aa99a, #5371b8, #8c5ca3, #ef665c); clip-path: polygon(50% 2%, 61% 34%, 96% 31%, 68% 52%, 80% 89%, 50% 67%, 19% 90%, 31% 52%, 4% 31%, 39% 34%); }
        .lg-credit { position: absolute; z-index: 8; left: 50%; top: calc(54% + min(22vw, 250px)); transform: translateX(-50%); padding: .6rem 1rem; border-radius: 999px; color: #26231f; background: #fffaf0e8; font-size: clamp(.72rem, 1vw, .95rem); box-shadow: 0 10px 30px #0005; }
        .lg-status { position: absolute; z-index: 10; right: 3vw; bottom: 3vh; display: flex; gap: .55rem; align-items: center; padding: .55rem .8rem; border: 1px solid #ffffff25; border-radius: 999px; background: #111a; backdrop-filter: blur(10px); font-size: .72rem; }
        .lg-dot { width: .55rem; height: .55rem; border-radius: 50%; background: #7de3a1; box-shadow: 0 0 14px #7de3a1; }
        .lg-manage { position:absolute; z-index:20; left:3vw; bottom:3vh; color:#fff9; font-size:.75rem; text-decoration:none; }
        @keyframes lg-drift { to { translate: 0 -18px; rotate: 1.2deg; } }
        @keyframes lg-breathe { 50% { transform: translate(-50%, -52%) rotate(-.5deg) scale(1.015); } }
        @media (prefers-reduced-motion: reduce) { .lg-moment, .lg-art { animation: none; } }
      </style>

      <div class="lg-grain"></div>
      <div class="lg-title">Living Gallery<strong>{@instance_name}</strong></div>
      <%= if @moments == [] do %>
        <div class="lg-moment lg-m1" data-label="Workshop moment"></div>
        <div class="lg-moment lg-m2" data-label="Making together"></div>
        <div class="lg-moment lg-m3" data-label="In progress"></div>
      <% else %>
        <div :for={{item, index} <- Enum.with_index(@moments)} class={"lg-moment lg-m#{rem(index, 3) + 1}"} data-label={item.title || "Workshop moment"}>
          <img src={"#{@media_base_url}/#{item.filename}"} style="width:100%;height:100%;object-fit:cover;display:block" />
        </div>
      <% end %>
      <%= if artwork = List.first(@artworks) do %>
        <div class="lg-art"><img src={"#{@media_base_url}/#{artwork.filename}"} style="width:100%;height:100%;object-fit:contain;display:block" /></div>
        <div :if={artwork.show_attribution && artwork.creator_name} class="lg-credit">Created by {artwork.creator_name}</div>
      <% else %>
        <div class="lg-art"><div class="lg-art-image"></div></div>
        <div class="lg-credit">Waiting for the first artwork</div>
      <% end %>
      <a class="lg-manage" href="/manage">← Manage kiosk</a>
      <div class="lg-status"><span class="lg-dot"></span> Instance #{@instance_id} · live preview</div>
    </div>
    """
  end
end
