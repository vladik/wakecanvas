import Config

config :wake_canvas_experience_living_gallery,
  ecto_repos: [WakeCanvas.Experience.LivingGallery.Repo]

config :esbuild,
  version: "0.25.4",
  living_gallery: [
    args: ~w(
      js/variants/drifting-collage.js
      js/variants/quiet-spotlight.js
      js/variants/gallery-orbit.js
      js/variants/growing-canvas.js
      js/variants/community-tapestry.js
      --bundle
      --splitting
      --format=esm
      --target=es2022
      --outdir=../priv/static/variants
      --chunk-names=../chunks/[name]-[hash]
    ),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [
        Path.expand("../node_modules", __DIR__),
        Path.expand("../deps", __DIR__),
        Mix.Project.build_path()
      ]
    }
  ],
  living_gallery_media: [
    args: ~w(
      js/media/artwork-media.ts
      js/media/media-worker.ts
      --bundle
      --format=esm
      --target=es2022
      --outdir=../priv/static/media
    ),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../node_modules", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  living_gallery: [
    args: ~w(
      --input=assets/css/experience.css
      --output=priv/static/experience.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
