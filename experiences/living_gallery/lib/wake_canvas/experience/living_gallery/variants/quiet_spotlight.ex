defmodule WakeCanvas.Experience.LivingGallery.Variants.QuietSpotlight do
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="qs-wall" data-wakecanvas-experience="living-gallery" data-display-variant="quiet-spotlight">
      <style>
        body { margin: 0; overflow: hidden; background: #0d0e0c; }
        .qs-wall { position:relative; min-height:100vh; overflow:hidden; color:#f7f0e3; font-family:ui-sans-serif,system-ui; background:radial-gradient(circle at 50% 44%,#473d2f 0,transparent 33%),linear-gradient(145deg,#151713,#090a09); }
        .qs-heading { position:absolute; z-index:5; top:5vh; left:50%; translate:-50% 0; text-align:center; text-transform:uppercase; letter-spacing:.24em; font-size:clamp(.65rem,.9vw,.9rem); opacity:.72; }
        .qs-heading strong { display:block; margin-top:.6rem; font:500 clamp(1.8rem,3vw,3.6rem)/1 Georgia,serif; text-transform:none; letter-spacing:-.03em; opacity:1; }
        .qs-art { position:absolute; z-index:4; left:50%; top:50%; translate:-50% -47%; width:min(48vw,680px); height:min(65vh,720px); padding:clamp(12px,1.5vw,24px); background:#f9f5ea; box-shadow:0 45px 130px #000,0 0 80px #d4ad6b22; animation:qs-breathe 9s ease-in-out infinite; }
        .qs-art img { display:block; width:100%; height:100%; object-fit:contain; }
        .qs-empty { width:100%; height:100%; background:radial-gradient(circle at 50% 45%,#e9c569,transparent 16%),linear-gradient(135deg,#9b5c51,#426d69); }
        .qs-moment { position:absolute; width:clamp(90px,11vw,190px); aspect-ratio:4/3; padding:6px; background:#d7cdbd; opacity:.43; filter:saturate(.55); box-shadow:0 18px 55px #0009; }
        .qs-moment img { width:100%; height:100%; object-fit:cover; }
        .qs-moment:nth-child(1) { left:6vw; top:20vh; rotate:-5deg; }
        .qs-moment:nth-child(2) { right:7vw; top:25vh; rotate:4deg; }
        .qs-moment:nth-child(3) { left:10vw; bottom:10vh; rotate:3deg; }
        .qs-moment:nth-child(4) { right:10vw; bottom:9vh; rotate:-4deg; }
        .qs-credit { position:absolute; z-index:6; left:50%; bottom:5vh; translate:-50% 0; padding:.55rem 1rem; border:1px solid #fff2; border-radius:999px; background:#080908bb; backdrop-filter:blur(10px); font-size:.82rem; }
        .qs-status { position:absolute; z-index:8; right:2vw; bottom:2vh; font-size:.68rem; opacity:.55; }
        .qs-manage { position:absolute; z-index:8; left:2vw; bottom:2vh; color:#fff8; font-size:.72rem; text-decoration:none; }
        @keyframes qs-breathe { 50% { translate:-50% -49%; scale:1.008; } }
        @media (prefers-reduced-motion:reduce) { .qs-art { animation:none; } }
      </style>

      <div class="qs-heading">Quiet Spotlight<strong>{@instance_name}</strong></div>
      <div>
        <div :for={item <- Enum.take(@moments, 4)} class="qs-moment">
          <img src={"#{@media_base_url}/#{item.filename}"} />
        </div>
      </div>
      <%= if artwork = List.first(@artworks) do %>
        <div class="qs-art"><img src={"#{@media_base_url}/#{artwork.filename}"} /></div>
        <div :if={artwork.show_attribution && artwork.creator_name} class="qs-credit">Created by {artwork.creator_name}</div>
      <% else %>
        <div class="qs-art"><div class="qs-empty"></div></div>
        <div class="qs-credit">Waiting for the first artwork</div>
      <% end %>
      <a class="qs-manage" href="/manage">← Manage kiosk</a>
      <div class="qs-status">Instance #{@instance_id} · Quiet Spotlight</div>
    </div>
    """
  end
end
