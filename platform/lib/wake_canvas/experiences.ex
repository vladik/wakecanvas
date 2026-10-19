defmodule WakeCanvas.Experiences do
  import Ecto.Query

  alias WakeCanvas.Experiences.{
    ActiveInstanceManager,
    Instance,
    InstanceArchive,
    InstancePaths,
    Package,
    PackageArchive
  }

  alias WakeCanvas.Access
  alias WakeCanvas.Repo

  def list_packages do
    Package |> order_by([package], package.name) |> preload(:instances) |> Repo.all()
  end

  @doc false
  def register_development_package(definition) do
    attrs = %{
      id: definition.id,
      name: definition.name,
      version: definition.version,
      status: "installed",
      diagnostic: nil
    }

    case Repo.get(Package, definition.id) do
      nil -> %Package{} |> Package.changeset(attrs) |> Repo.insert()
      package -> package |> Package.changeset(attrs) |> Repo.update()
    end
  end

  def stage_package_install(archive_path) do
    with {:ok, artifact} <- PackageArchive.stage(archive_path),
         :ok <- ensure_no_module_collisions(artifact) do
      manifest = artifact.manifest
      id = manifest["experienceId"]

      Repo.transaction(fn ->
        case Repo.get(Package, id) do
          nil ->
            %Package{}
            |> Package.changeset(%{
              id: id,
              name: manifest["name"],
              version: manifest["version"],
              status: "pending_restart",
              archive_digest: artifact.digest,
              manifest: manifest,
              diagnostic: nil
            })
            |> Repo.insert!()

          %Package{} = package ->
            if package.archive_digest == artifact.digest do
              package
            else
              {previous_digest, previous_manifest} = upgrade_rollback_point(package)

              package
              |> Package.changeset(%{
                name: manifest["name"],
                version: manifest["version"],
                status: "pending_restart",
                previous_archive_digest: previous_digest,
                previous_manifest: previous_manifest,
                archive_digest: artifact.digest,
                manifest: manifest,
                diagnostic: nil
              })
              |> Repo.update!()
            end
        end
      end)
    end
  end

  def rollback_package(id) do
    case Repo.get(Package, id) do
      nil ->
        {:error, :not_found}

      %Package{previous_archive_digest: nil} ->
        {:error, :no_rollback_available}

      %Package{} = package ->
        with {:ok, artifact} <- PackageArchive.validate_cache(package.previous_archive_digest),
             true <- artifact.manifest["experienceId"] == package.id,
             :ok <- ensure_no_module_collisions(artifact) do
          package
          |> Package.changeset(%{
            name: artifact.manifest["name"],
            version: artifact.manifest["version"],
            status: "pending_restart",
            archive_digest: package.previous_archive_digest,
            manifest: artifact.manifest,
            previous_archive_digest: package.archive_digest,
            previous_manifest: package.manifest,
            diagnostic: nil
          })
          |> Repo.update()
        else
          false -> {:error, :rollback_identity_mismatch}
          error -> error
        end
    end
  end

  def uninstall_package(id, confirmation) when is_binary(confirmation) do
    case Repo.get(Package, id) |> preload_instances() do
      nil ->
        {:error, :not_found}

      %Package{archive_digest: nil} ->
        {:error, :source_linked_package}

      %Package{name: name} when name != confirmation ->
        {:error, :confirmation_mismatch}

      %Package{instances: instances} when instances != [] ->
        {:error, {:instances_exist, length(instances)}}

      %Package{} = package ->
        case Repo.delete(package) do
          {:ok, deleted} ->
            cleanup_unreferenced_package_caches([
              package.archive_digest,
              package.previous_archive_digest
            ])

            {:ok, deleted}

          error ->
            error
        end
    end
  end

  defp upgrade_rollback_point(%Package{status: "pending_restart"} = package) do
    {
      package.previous_archive_digest || package.archive_digest,
      package.previous_manifest || package.manifest
    }
  end

  defp upgrade_rollback_point(package), do: {package.archive_digest, package.manifest}

  defp cleanup_unreferenced_package_caches(digests) do
    digests
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(fn digest ->
      referenced =
        Repo.exists?(
          from package in Package,
            where: package.archive_digest == ^digest or package.previous_archive_digest == ^digest
        )

      if not referenced, do: PackageArchive.remove_cache(digest)
    end)
  end

  defp preload_instances(nil), do: nil
  defp preload_instances(package), do: Repo.preload(package, :instances)

  defp ensure_no_module_collisions(artifact) do
    id = artifact.manifest["experienceId"]
    incoming = PackageArchive.beam_modules(artifact.files)

    existing =
      Package
      |> where([package], package.id != ^id and not is_nil(package.archive_digest))
      |> select([package], package.archive_digest)
      |> Repo.all()
      |> Enum.reduce(MapSet.new(), fn digest, modules ->
        MapSet.union(modules, PackageArchive.cached_beam_modules(digest))
      end)

    reserved =
      Enum.filter(incoming, fn module ->
        String.starts_with?(module, "Elixir.WakeCanvasWeb.") or
          String.starts_with?(module, "Elixir.WakeCanvas.Experiences.") or
          String.starts_with?(module, "Elixir.WakeCanvas.ExperienceSDK.") or
          module in ["Elixir.WakeCanvas.Application", "Elixir.WakeCanvas.Repo"]
      end)

    collisions = MapSet.intersection(incoming, existing) |> MapSet.to_list()

    case Enum.sort(reserved ++ collisions) do
      [] -> :ok
      modules -> {:error, {:module_collision, Enum.uniq(modules)}}
    end
  end

  def list_instances do
    Instance
    |> where([instance], is_nil(instance.archived_at))
    |> preload(:package)
    |> order_by([instance], asc: instance.name, asc: instance.id)
    |> Repo.all()
  end

  def list_archived_instances do
    Instance
    |> where([instance], not is_nil(instance.archived_at))
    |> preload(:package)
    |> order_by([instance], desc: instance.archived_at)
    |> Repo.all()
  end

  def get_instance(reference) when is_binary(reference) do
    query = where(Instance, [instance], is_nil(instance.archived_at))

    instance =
      case Ecto.UUID.cast(reference) do
        {:ok, id} ->
          if id == String.downcase(reference),
            do: Repo.get(query, id),
            else: Repo.get_by(query, slug: reference)

        :error ->
          Repo.get_by(query, slug: reference)
      end

    preload_package(instance)
  end

  def get_instance!(id), do: get_instance(id) || raise(Ecto.NoResultsError, queryable: Instance)

  def active_instance do
    Instance
    |> where([instance], instance.active and is_nil(instance.archived_at))
    |> Repo.one()
    |> preload_package()
  end

  def change_instance(instance, attrs \\ %{}), do: Instance.changeset(instance, attrs)

  def update_instance_config(%Instance{} = instance, patch) when is_map(patch) do
    instance
    |> Ecto.Changeset.change(config: Map.merge(instance.config, patch))
    |> Repo.update()
  end

  def set_participant_code(id, code) do
    with %Instance{} = instance <- get_instance(id),
         {:ok, changeset} <- Access.participant_code_change(instance, code) do
      Repo.update(changeset)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def create_instance(attrs) do
    %Instance{}
    |> Instance.changeset(attrs)
    |> Repo.insert()
  end

  def export_instance(id) when is_binary(id) do
    case Repo.get(Instance, id) |> preload_package() do
      nil -> {:error, :not_found}
      instance -> InstanceArchive.export(instance)
    end
  end

  @doc """
  Imports a portable instance archive. Imported instances are always archived and
  inactive so an operator can inspect them before restoring or starting them.

  `:preserve` retains the archive UUID, `:clone` assigns a new UUID, and
  `:replace` requires the exact name of an existing archived instance.
  """
  def import_instance(archive_path, mode \\ :preserve, confirmation \\ "")
      when mode in [:preserve, :clone, :replace] do
    with {:ok, staged} <- InstanceArchive.stage(archive_path) do
      try do
        import_staged_instance(staged, mode, confirmation)
      after
        _ = InstanceArchive.cleanup(staged)
      end
    end
  end

  def activate_instance(id) do
    next = get_instance!(id)
    previous = active_instance()

    with :ok <- ActiveInstanceManager.switch(next) do
      case Repo.transaction(fn ->
             Repo.update_all(from(instance in Instance, where: instance.active),
               set: [active: false]
             )

             next
             |> Ecto.Changeset.change(active: true)
             |> Repo.update!()
           end) do
        {:ok, activated} ->
          {:ok, activated}

        {:error, reason} ->
          rollback_runtime(previous)
          {:error, reason}
      end
    end
  end

  def stop_instance(id) do
    instance = get_instance!(id)

    with :ok <- ActiveInstanceManager.stop(instance.id) do
      case instance |> Ecto.Changeset.change(active: false) |> Repo.update() do
        {:ok, stopped} ->
          {:ok, stopped}

        {:error, reason} ->
          ActiveInstanceManager.switch(instance)
          {:error, reason}
      end
    end
  end

  def archive_instance(id) do
    instance = get_instance!(id)

    if instance.active do
      {:error, :active_instance}
    else
      instance
      |> Ecto.Changeset.change(archived_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
    end
  end

  def restore_instance(id) do
    case Repo.get(Instance, id) do
      nil -> {:error, :not_found}
      instance -> instance |> Ecto.Changeset.change(archived_at: nil) |> Repo.update()
    end
  end

  def purge_instance(id, confirmation) when is_binary(confirmation) do
    case Repo.get(Instance, id) |> preload_package() do
      nil ->
        {:error, :not_found}

      %Instance{archived_at: nil} ->
        {:error, :not_archived}

      %Instance{name: name} when name != confirmation ->
        {:error, :confirmation_mismatch}

      %Instance{} = instance ->
        with {:ok, staged} <- InstancePaths.stage_for_deletion(instance.id),
             {:ok, _deleted} <- delete_staged_instance(instance, staged) do
          # The row is already gone and the directory is outside the live namespace.
          # A failed final removal is safe and will be retried on the next startup.
          _ = InstancePaths.finalize(staged)
          {:ok, instance}
        end
    end
  end

  defp delete_staged_instance(instance, staged) do
    case Repo.delete(instance) do
      {:ok, deleted} ->
        {:ok, deleted}

      {:error, reason} ->
        _ = InstancePaths.restore(staged)
        {:error, reason}
    end
  end

  defp import_staged_instance(staged, mode, confirmation) do
    metadata = staged.manifest["instance"]
    source_id = metadata["id"]

    with %Package{status: "installed"} = package <-
           Repo.get(Package, metadata["experienceId"]) ||
             {:error, {:package_not_installed, metadata["experienceId"]}},
         true <-
           package.version == metadata["experienceVersion"] ||
             {:error, {:package_version_mismatch, package.version, metadata["experienceVersion"]}} do
      case mode do
        :preserve ->
          if Repo.get(Instance, source_id),
            do: {:error, :instance_exists},
            else: import_new_instance(staged, metadata, source_id, false)

        :clone ->
          import_new_instance(staged, metadata, Ecto.UUID.generate(), true)

        :replace ->
          replace_instance(staged, metadata, confirmation)
      end
    else
      {:error, _} = error -> error
      _ -> {:error, {:package_not_installed, metadata["experienceId"]}}
    end
  end

  defp import_new_instance(staged, metadata, target_id, clone?) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    destination = InstancePaths.data_dir(target_id)
    File.mkdir_p!(Path.dirname(destination))

    attrs = %{
      name: if(clone?, do: "#{metadata["name"]} (Copy)", else: metadata["name"]),
      slug: if(clone?, do: nil, else: available_slug(metadata["slug"], nil)),
      experience_id: metadata["experienceId"],
      config: metadata["config"]
    }

    changeset =
      %Instance{id: target_id}
      |> Instance.changeset(attrs)
      |> Ecto.Changeset.change(
        active: false,
        archived_at: now,
        participant_code_digest: metadata["participantCodeDigest"],
        participant_code_version: metadata["participantCodeVersion"]
      )

    with :ok <- ensure_destination_absent(destination),
         :ok <- File.rename(staged.content_dir, destination),
         {:ok, instance} <- Repo.insert(changeset) do
      {:ok, preload_package(instance)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        _ = File.rm_rf(destination)
        {:error, changeset}

      error ->
        error
    end
  end

  defp replace_instance(staged, metadata, confirmation) do
    case Repo.get(Instance, metadata["id"]) do
      nil ->
        {:error, :not_found}

      %Instance{archived_at: nil} ->
        {:error, :not_archived}

      %Instance{name: name} when name != confirmation ->
        {:error, :confirmation_mismatch}

      %Instance{} = existing ->
        replace_archived_instance(staged, metadata, existing)
    end
  end

  defp replace_archived_instance(staged, metadata, existing) do
    destination = InstancePaths.data_dir(existing.id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset =
      existing
      |> Instance.changeset(%{
        name: metadata["name"],
        slug: available_slug(metadata["slug"], existing.id),
        experience_id: metadata["experienceId"],
        config: metadata["config"]
      })
      |> Ecto.Changeset.change(
        active: false,
        archived_at: now,
        participant_code_digest: metadata["participantCodeDigest"],
        participant_code_version: metadata["participantCodeVersion"]
      )

    case InstancePaths.stage_for_deletion(existing.id) do
      {:ok, previous} ->
        case File.rename(staged.content_dir, destination) do
          :ok ->
            case Repo.update(changeset) do
              {:ok, instance} ->
                _ = InstancePaths.finalize(previous)
                {:ok, preload_package(instance)}

              {:error, reason} ->
                _ = File.rm_rf(destination)
                _ = InstancePaths.restore(previous)
                {:error, reason}
            end

          {:error, reason} ->
            _ = InstancePaths.restore(previous)
            {:error, reason}
        end

      error ->
        error
    end
  end

  defp ensure_destination_absent(path) do
    if File.exists?(path), do: {:error, :instance_storage_exists}, else: :ok
  end

  defp available_slug(nil, _except_id), do: nil

  defp available_slug(slug, except_id) when is_binary(slug) do
    conflict =
      if except_id do
        Repo.exists?(
          from instance in Instance, where: instance.slug == ^slug and instance.id != ^except_id
        )
      else
        Repo.exists?(from instance in Instance, where: instance.slug == ^slug)
      end

    if conflict, do: nil, else: slug
  end

  defp preload_package(nil), do: nil
  defp preload_package(instance), do: Repo.preload(instance, :package)

  defp rollback_runtime(nil), do: :ok
  defp rollback_runtime(instance), do: ActiveInstanceManager.switch(instance)
end
