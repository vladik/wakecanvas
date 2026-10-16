defmodule WakeCanvas.Experiences.InstancePaths do
  def data_dir(instance_id) when is_integer(instance_id) do
    :wake_canvas
    |> Application.fetch_env!(:data_root)
    |> Path.join("instances")
    |> Path.join(Integer.to_string(instance_id))
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
end
