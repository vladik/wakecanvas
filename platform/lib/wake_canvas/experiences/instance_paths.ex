defmodule WakeCanvas.Experiences.InstancePaths do
  def data_dir(instance_id) when is_binary(instance_id) do
    instance_id = canonical_uuid!(instance_id)

    :wake_canvas
    |> Application.fetch_env!(:data_root)
    |> Path.join("instances")
    |> Path.join(instance_id)
    |> Path.expand()
  end

  def database_path(instance_id), do: Path.join(data_dir(instance_id), "experience.sqlite")
  def media_dir(instance_id), do: Path.join(data_dir(instance_id), "media")

  def ensure!(instance_id) do
    File.mkdir_p!(media_dir(instance_id))
    :ok
  end

  def stage_for_deletion(instance_id) do
    source = data_dir(instance_id)

    if File.exists?(source) do
      deletion_root = Path.join(Application.fetch_env!(:wake_canvas, :data_root), "deleting")
      File.mkdir_p!(deletion_root)
      staged = Path.join(deletion_root, "#{instance_id}-#{System.unique_integer([:positive])}")

      case File.rename(source, staged) do
        :ok -> {:ok, {source, staged}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  def restore(nil), do: :ok
  def restore({source, staged}), do: File.rename(staged, source)

  def finalize(nil), do: :ok

  def finalize({_source, staged}) do
    case File.rm_rf(staged) do
      {:ok, _paths} -> :ok
      {:error, reason, _path} -> {:error, reason}
    end
  end

  def cleanup_staged_deletions do
    deletion_root = Path.join(Application.fetch_env!(:wake_canvas, :data_root), "deleting")

    case File.ls(deletion_root) do
      {:ok, entries} ->
        Enum.each(entries, fn entry -> File.rm_rf(Path.join(deletion_root, entry)) end)
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cleanup_transient_archives do
    Enum.reduce_while(["importing", "exports"], :ok, fn directory, :ok ->
      root = Path.join(Application.fetch_env!(:wake_canvas, :data_root), directory)

      case File.rm_rf(root) do
        {:ok, _paths} -> {:cont, :ok}
        {:error, reason, _path} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp canonical_uuid!(instance_id) do
    case Ecto.UUID.cast(instance_id) do
      {:ok, uuid} -> uuid
      :error -> raise ArgumentError, "invalid Experience instance UUID"
    end
  end
end
