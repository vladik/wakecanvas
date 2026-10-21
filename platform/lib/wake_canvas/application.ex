defmodule WakeCanvas.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    _ = WakeCanvas.Experiences.InstancePaths.cleanup_staged_deletions()
    _ = WakeCanvas.Experiences.InstancePaths.cleanup_transient_archives()

    children = [
      WakeCanvasWeb.Telemetry,
      WakeCanvas.Repo,
      WakeCanvas.Access.AttemptLimiter,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:wake_canvas, :ecto_repos), skip: skip_migrations?()},
      WakeCanvas.Experiences.BundledPackageInstaller,
      {DNSCluster, query: Application.get_env(:wake_canvas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WakeCanvas.PubSub},
      WakeCanvas.Diagnostics.RendererMonitor,
      WakeCanvas.Experiences.Registry,
      {WakeCanvas.Experiences.ActiveInstanceSupervisor,
       name: WakeCanvas.Experiences.ActiveInstanceSupervisor},
      WakeCanvas.Experiences.ActiveInstanceManager,
      WakeCanvas.Experiences.BundledInstanceInstaller,
      # Start a worker by calling: WakeCanvas.Worker.start_link(arg)
      # {WakeCanvas.Worker, arg},
      # Start to serve requests, typically the last entry
      WakeCanvasWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WakeCanvas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WakeCanvasWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
