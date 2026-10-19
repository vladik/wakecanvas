import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :wake_canvas, WakeCanvas.Repo,
  database: Path.expand("../wake_canvas_test.db", __DIR__),
  pool_size: 1,
  pool: Ecto.Adapters.SQL.Sandbox

config :wake_canvas, :data_root, Path.expand("../tmp/test-data", __DIR__)
config :wake_canvas, :restore_active_instance, false

config :wake_canvas, :development_experiences, [
  %{
    entry_module: "WakeCanvas.TestExperience",
    ebin: Path.expand("../_build/test/lib/wake_canvas/ebin", __DIR__)
  }
]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :wake_canvas, WakeCanvasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "iBX+miCjyGPbCxrIFSrBxtWfjlXN1K4PL/037WOuFuPUi66x/Ih79NpGrBN7aiOx",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
