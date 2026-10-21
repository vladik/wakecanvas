defmodule WakeCanvas.Experiences.BundledInstanceInstaller do
  @moduledoc """
  Imports portable instance archives bundled with a release.

  Import is intentionally UUID-idempotent. Once a seed is known to the platform,
  later starts never replace its files or operator changes.
  """

  use GenServer

  require Logger

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.InstanceArchive

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    directory = Keyword.get(opts, :directory, bundled_instance_directory())
    auto_activate = Keyword.get(opts, :auto_activate, auto_activate_seed?())
    result = install_from(directory, auto_activate)
    {:ok, Map.put(result, :directory, directory)}
  end

  @doc false
  def install_from(directory, auto_activate \\ false)

  def install_from(nil, _auto_activate), do: %{archives: [], activation: :disabled}

  def install_from(directory, auto_activate) when is_binary(directory) do
    archives =
      directory
      |> Path.expand()
      |> Path.join("*.wakecanvas-instance")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&install_archive/1)

    activation = maybe_activate(archives, auto_activate)
    %{archives: archives, activation: activation}
  end

  defp install_archive(archive) do
    result =
      with {:ok, id} <- archive_instance_id(archive) do
        case Experiences.get_instance_including_archived(id) do
          nil ->
            case Experiences.import_instance(archive, :preserve) do
              {:ok, instance} -> {:imported, instance}
              error -> error
            end

          instance ->
            {:skipped, instance}
        end
      end

    case result do
      {:imported, instance} ->
        Logger.info("Bundled instance imported: #{instance.id} #{instance.name}")

      {:skipped, instance} ->
        Logger.info("Bundled instance already managed: #{instance.id} #{instance.name}")

      {:error, reason} ->
        Logger.error("Bundled instance rejected: #{Path.basename(archive)} #{inspect(reason)}")
    end

    {archive, result}
  end

  defp archive_instance_id(archive) do
    with {:ok, staged} <- InstanceArchive.stage(archive) do
      try do
        case get_in(staged.manifest, ["instance", "id"]) do
          id when is_binary(id) -> {:ok, id}
          _ -> {:error, :missing_instance_id}
        end
      after
        _ = InstanceArchive.cleanup(staged)
      end
    end
  end

  defp maybe_activate(_archives, false), do: :disabled

  defp maybe_activate(archives, true) do
    if Experiences.active_instance() do
      :active_instance_preserved
    else
      imported =
        Enum.find_value(archives, fn
          {_archive, {:imported, instance}} -> instance
          _ -> nil
        end)

      if imported do
        activate_seed(imported)
      else
        if Enum.any?(archives, &match?({_archive, {:skipped, _instance}}, &1)),
          do: :seed_already_imported,
          else: :no_seed
      end
    end
  end

  defp activate_seed(instance) do
    with {:ok, _instance} <- maybe_restore(instance),
         {:ok, activated} <- Experiences.activate_instance(instance.id) do
      Logger.info("Bundled instance activated: #{activated.id} #{activated.name}")
      {:activated, activated}
    else
      {:error, reason} = error ->
        Logger.error("Bundled instance could not be activated: #{instance.id} #{inspect(reason)}")
        error
    end
  end

  defp maybe_restore(%{archived_at: nil} = instance), do: {:ok, instance}
  defp maybe_restore(instance), do: Experiences.restore_instance(instance.id)

  defp bundled_instance_directory do
    System.get_env("WAKECANVAS_BUNDLED_INSTANCES") ||
      case System.get_env("RELEASE_ROOT") do
        nil -> nil
        release_root -> Path.join(release_root, "seeds")
      end
  end

  defp auto_activate_seed? do
    System.get_env("WAKECANVAS_AUTO_ACTIVATE_SEED", "false")
    |> String.downcase()
    |> then(&(&1 in ["1", "true", "yes", "on"]))
  end
end
