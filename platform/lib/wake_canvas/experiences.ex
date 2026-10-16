defmodule WakeCanvas.Experiences do
  import Ecto.Query

  alias WakeCanvas.Experiences.{Instance, Package}
  alias WakeCanvas.Repo

  def list_packages do
    Package |> order_by([package], package.name) |> Repo.all()
  end

  def list_instances do
    Instance
    |> where([instance], is_nil(instance.archived_at))
    |> preload(:package)
    |> order_by([instance], instance.id)
    |> Repo.all()
  end

  def list_archived_instances do
    Instance
    |> where([instance], not is_nil(instance.archived_at))
    |> preload(:package)
    |> order_by([instance], desc: instance.archived_at)
    |> Repo.all()
  end

  def get_instance(id) do
    Instance
    |> where([instance], is_nil(instance.archived_at))
    |> Repo.get(id)
    |> preload_package()
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

  def create_instance(attrs) do
    %Instance{}
    |> Instance.changeset(attrs)
    |> Repo.insert()
  end

  def activate_instance(id) do
    Repo.transaction(fn ->
      Repo.update_all(from(instance in Instance, where: instance.active), set: [active: false])

      id
      |> get_instance!()
      |> Ecto.Changeset.change(active: true)
      |> Repo.update!()
    end)
  end

  def stop_instance(id) do
    id
    |> get_instance!()
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
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

  defp preload_package(nil), do: nil
  defp preload_package(instance), do: Repo.preload(instance, :package)
end
