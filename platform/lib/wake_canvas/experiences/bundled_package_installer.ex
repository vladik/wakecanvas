defmodule WakeCanvas.Experiences.BundledPackageInstaller do
  @moduledoc false

  use GenServer

  require Logger

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.{Package, PackageArchive}
  alias WakeCanvas.Repo

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    directory = Keyword.get(opts, :directory, bundled_package_directory())
    results = install_from(directory)
    {:ok, %{directory: directory, results: results}}
  end

  @doc false
  def install_from(nil), do: []

  def install_from(directory) when is_binary(directory) do
    directory
    |> Path.join("*.wakecanvas")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn archive ->
      result = stage_seed_package(archive)

      case result do
        {:ok, package} ->
          Logger.info("Bundled Experience staged: #{package.id} #{package.version}")

        {:skipped, package} ->
          Logger.info("Bundled Experience already managed: #{package.id} #{package.version}")

        {:error, reason} ->
          Logger.error(
            "Bundled Experience rejected: #{Path.basename(archive)} #{inspect(reason)}"
          )
      end

      {archive, result}
    end)
  end

  defp stage_seed_package(archive) do
    with {:ok, artifact} <- PackageArchive.validate(archive) do
      package = Repo.get(Package, artifact.manifest["experienceId"])

      if should_stage?(package, artifact.digest) do
        Experiences.stage_package_install(archive)
      else
        {:skipped, package}
      end
    end
  end

  @doc false
  def should_stage?(nil, _bundled_digest), do: true

  def should_stage?(%Package{archive_digest: digest}, digest) when is_binary(digest), do: true

  def should_stage?(%Package{status: "rejected"}, _bundled_digest), do: true
  def should_stage?(%Package{}, _bundled_digest), do: false

  defp bundled_package_directory do
    System.get_env("WAKECANVAS_BUNDLED_PACKAGES") ||
      case System.get_env("RELEASE_ROOT") do
        nil -> nil
        release_root -> Path.join(release_root, "packages")
      end
  end
end
