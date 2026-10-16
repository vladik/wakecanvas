import Config

config :wake_canvas_experience_living_gallery,
  ecto_repos: [WakeCanvas.Experience.LivingGallery.Repo]

config :esbuild,
  version: "0.25.4",
  living_gallery: [
    args: ~w(js/experience.js --bundle --target=es2022 --outfile=../priv/static/experience.js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
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
