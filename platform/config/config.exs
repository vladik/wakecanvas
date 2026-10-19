# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :wake_canvas,
  ecto_repos: [WakeCanvas.Repo],
  generators: [timestamp_type: :utc_datetime],
  data_root: Path.expand("../data", __DIR__)

config :wake_canvas, WakeCanvas.Repo,
  journal_mode: :wal,
  busy_timeout: 10_000

# Configure the endpoint
config :wake_canvas, WakeCanvasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WakeCanvasWeb.ErrorHTML, json: WakeCanvasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WakeCanvas.PubSub,
  live_view: [signing_salt: "qQs7cJFg"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# WakeCanvas does not import third-party modules from the generated colocated-assets
# node_modules link. Avoid requiring Windows developer-mode symlink privileges.
config :phoenix_live_view, :colocated_assets, disable_symlink_warning: true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  wake_canvas: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  wake_canvas: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/vnd.wakecanvas.experience+zip" => ["wakecanvas"],
  "application/vnd.wakecanvas.instance+zip" => ["wakecanvas-instance"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
