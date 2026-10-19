import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/wake_canvas start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") || System.get_env("RELEASE_NAME") do
  config :wake_canvas, WakeCanvasWeb.Endpoint, server: true
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :wake_canvas, WakeCanvasWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/wake_canvas_web/router\.ex$"E,
        ~r"lib/wake_canvas_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  release_root = System.get_env("RELEASE_ROOT")

  data_root =
    System.get_env("WAKECANVAS_DATA_ROOT") ||
      if release_root do
        Path.join(release_root, "data")
      else
        Path.expand("../.tmp/prod-data", __DIR__)
      end

  config_root = Path.join(data_root, "config")
  File.mkdir_p!(config_root)

  database_path = System.get_env("DATABASE_PATH") || Path.join(data_root, "wake_canvas.sqlite3")

  management_code =
    case System.get_env("WAKECANVAS_MANAGEMENT_CODE") do
      nil ->
        case File.read(Path.join(config_root, "management_code")) do
          {:ok, code} -> String.trim(code)
          {:error, :enoent} -> ""
          {:error, reason} -> raise "cannot read management code: #{inspect(reason)}"
        end

      code ->
        String.trim(code)
    end

  config :wake_canvas,
    data_root: data_root,
    management_code: management_code

  config :wake_canvas, WakeCanvas.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "1")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    case System.get_env("SECRET_KEY_BASE") do
      nil when not is_nil(release_root) ->
        secret_path = Path.join(config_root, "secret_key_base")

        case File.read(secret_path) do
          {:ok, secret} ->
            String.trim(secret)

          {:error, :enoent} ->
            secret = :crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)
            File.write!(secret_path, secret <> "\n")
            secret

          {:error, reason} ->
            raise "cannot read kiosk secret: #{inspect(reason)}"
        end

      nil ->
        # Compile-time Mix commands load runtime.exs without running a release.
        String.duplicate("build-only-secret-", 4)

      secret ->
        secret
    end

  host = System.get_env("PHX_HOST") || "localhost"
  scheme = System.get_env("PHX_SCHEME") || "http"
  port = String.to_integer(System.get_env("PORT", "4000"))
  url_port = String.to_integer(System.get_env("PHX_URL_PORT", Integer.to_string(port)))
  bind_address = System.get_env("WAKECANVAS_BIND_IP", "0.0.0.0")

  bind_ip =
    case :inet.parse_address(String.to_charlist(bind_address)) do
      {:ok, address} ->
        address

      {:error, reason} ->
        raise "invalid WAKECANVAS_BIND_IP #{inspect(bind_address)}: #{inspect(reason)}"
    end

  config :wake_canvas, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :wake_canvas, WakeCanvasWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme],
    http: [ip: bind_ip, port: port],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :wake_canvas, WakeCanvasWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :wake_canvas, WakeCanvasWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
