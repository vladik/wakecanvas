defmodule WakeCanvas.Diagnostics do
  @moduledoc """
  Read-only operational checks for an unattended WakeCanvas installation.

  Checks deliberately stay at platform boundaries: the platform verifies its own
  catalog and counts Experience-owned files, but never opens an Experience SQLite
  database or interprets Experience content.
  """

  import Ecto.Query

  alias WakeCanvas.Diagnostics.RendererMonitor
  alias WakeCanvas.Experiences.{ActiveInstanceManager, Instance, InstancePaths, Package}
  alias WakeCanvas.Repo

  @storage_scan_limit 100_000
  @warning_used_percent 85
  @critical_used_percent 95
  @warning_free_bytes 2 * 1024 * 1024 * 1024
  @critical_free_bytes 512 * 1024 * 1024

  def snapshot do
    checks = [
      safe_check(:platform_database, "Platform database", &database_check/0),
      safe_check(:data_directory, "Data directory", &data_directory_check/0),
      safe_check(:disk_capacity, "Disk capacity", &disk_check/0),
      safe_check(:packages, "Experience packages", &package_check/0),
      safe_check(:active_runtime, "Active runtime", &runtime_check/0),
      safe_check(:renderer, "Display renderer", &renderer_check/0),
      safe_check(:instance_storage, "Instance storage", &instance_storage_check/0)
    ]

    %{
      status: overall_status(checks),
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      platform_version: Application.spec(:wake_canvas, :vsn) |> to_string(),
      node: node() |> to_string(),
      uptime_seconds: div(:erlang.statistics(:wall_clock) |> elem(0), 1_000),
      checks: checks
    }
  end

  def public_snapshot do
    report = snapshot()

    %{
      status: report.status,
      generated_at: report.generated_at,
      platform_version: report.platform_version,
      uptime_seconds: report.uptime_seconds,
      checks:
        Enum.map(report.checks, fn check ->
          %{id: check.id, status: check.status, message: public_message(check)}
        end)
    }
  end

  defp database_check do
    case Repo.query("PRAGMA quick_check", [], log: false) do
      {:ok, %{rows: [["ok"]]}} ->
        ok("SQLite quick check passed.")

      {:ok, %{rows: rows}} ->
        error("SQLite reported an integrity problem.", %{result: rows})

      {:error, reason} ->
        error("SQLite integrity check could not run.", %{reason: inspect(reason)})
    end
  end

  defp data_directory_check do
    root = Application.fetch_env!(:wake_canvas, :data_root) |> Path.expand()
    marker = Path.join(root, ".wakecanvas-write-check-#{System.unique_integer([:positive])}")

    with :ok <- File.mkdir_p(root),
         {:ok, device} <- File.open(marker, [:write, :exclusive, :binary]),
         :ok <- File.close(device),
         :ok <- File.rm(marker) do
      ok("The data directory is writable.", %{path: root})
    else
      {:error, reason} ->
        _ = File.rm(marker)
        error("The data directory is not writable.", %{reason: inspect(reason)})
    end
  end

  defp disk_check do
    root = Application.fetch_env!(:wake_canvas, :data_root) |> Path.expand()

    case matching_disk(root, :disksup.get_disk_data()) do
      nil ->
        warning("Disk capacity is unavailable on this operating system.")

      {mount, total_kb, used_percent} ->
        total_bytes = total_kb * 1_024
        free_bytes = div(total_bytes * (100 - used_percent), 100)

        details = %{
          mount: mount,
          total_bytes: total_bytes,
          free_bytes: free_bytes,
          used_percent: used_percent
        }

        message = "#{used_percent}% used; #{format_bytes(free_bytes)} free."

        cond do
          used_percent >= @critical_used_percent or free_bytes <= @critical_free_bytes ->
            error(message, details)

          used_percent >= @warning_used_percent or free_bytes <= @warning_free_bytes ->
            warning(message, details)

          true ->
            ok(message, details)
        end
    end
  end

  defp package_check do
    packages = Repo.all(Package)
    installed = Enum.count(packages, &(&1.status == "installed"))
    pending = Enum.count(packages, &(&1.status == "pending_restart"))
    rejected = Enum.count(packages, &(&1.status == "rejected"))
    details = %{installed: installed, pending_restart: pending, rejected: rejected}

    cond do
      rejected > 0 -> warning("#{rejected} package(s) failed to load.", details)
      pending > 0 -> warning("#{pending} package change(s) require a restart.", details)
      true -> ok("#{installed} Experience package(s) installed.", details)
    end
  end

  defp runtime_check do
    selected =
      Repo.one(from instance in Instance, where: instance.active and is_nil(instance.archived_at))

    runtime = ActiveInstanceManager.status()

    cond do
      is_nil(selected) and runtime.running ->
        warning("An Experience runtime is running without an active catalog selection.")

      is_nil(selected) ->
        ok("No instance is selected. Management remains available.")

      runtime.running and runtime.instance_id == selected.id and is_nil(runtime.last_error) ->
        ok("#{selected.name} is running.", %{instance_id: selected.id})

      runtime.running and runtime.instance_id == selected.id ->
        warning("#{selected.name} is running after a recorded runtime error.", %{
          instance_id: selected.id,
          reason: inspect(runtime.last_error)
        })

      true ->
        error("#{selected.name} is selected but its runtime is not running.", %{
          instance_id: selected.id,
          reason: inspect(runtime.last_error)
        })
    end
  end

  defp instance_storage_check do
    ids = Repo.all(from instance in Instance, select: instance.id)

    {bytes, files, errors, truncated} =
      Enum.reduce_while(ids, {0, 0, 0, false}, fn id, totals ->
        next = directory_usage(InstancePaths.data_dir(id), totals)
        if elem(next, 3), do: {:halt, next}, else: {:cont, next}
      end)

    details = %{
      instances: length(ids),
      files: files,
      bytes: bytes,
      scan_limit: @storage_scan_limit
    }

    cond do
      truncated ->
        warning("Instance storage exceeds the diagnostic scan limit.", details)

      errors > 0 ->
        warning(
          "#{errors} instance storage path(s) could not be read.",
          Map.put(details, :errors, errors)
        )

      true ->
        ok("#{length(ids)} instance(s), #{files} file(s), #{format_bytes(bytes)} used.", details)
    end
  end

  defp renderer_check do
    selected =
      Repo.one(from instance in Instance, where: instance.active and is_nil(instance.archived_at))

    if selected do
      reports = RendererMonitor.snapshot(selected.id)
      visible = Enum.filter(reports, & &1.visible)
      failed = Enum.filter(reports, &(&1.status in ["error", "context_lost"]))
      fallback = Enum.filter(reports, & &1.fallback)
      slow = Enum.filter(visible, &(is_number(&1.fps) and &1.fps < 20))
      latest = List.first(reports)

      details = %{
        clients: length(reports),
        visible_clients: length(visible),
        active_variant: latest && latest.active_variant,
        requested_variant: latest && latest.requested_variant,
        fps: latest && latest.fps,
        viewport: latest && %{width: latest.width, height: latest.height},
        fallback: latest && latest.fallback,
        webgl2: latest && latest.webgl2,
        last_seen_at: latest && latest.received_at
      }

      cond do
        reports == [] ->
          warning("No display heartbeat has been received for the active instance.", details)

        failed != [] ->
          error("#{length(failed)} display renderer(s) reported a failure.", details)

        fallback != [] ->
          warning(
            "#{length(fallback)} display renderer(s) are using a fallback variant.",
            details
          )

        slow != [] ->
          warning("#{length(slow)} visible display renderer(s) are below 20 FPS.", details)

        true ->
          fps = if latest.fps, do: " at #{Float.round(latest.fps, 1)} FPS", else: ""
          ok("#{length(reports)} display renderer(s) connected#{fps}.", details)
      end
    else
      ok("No active instance requires a display heartbeat.")
    end
  end

  defp directory_usage(_path, {bytes, files, errors, _truncated})
       when files >= @storage_scan_limit,
       do: {bytes, files, errors, true}

  defp directory_usage(path, totals) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} ->
        {bytes, files, errors, truncated} = totals
        {bytes + size, files + 1, errors, truncated}

      {:ok, %{type: :directory}} ->
        case File.ls(path) do
          {:ok, names} ->
            Enum.reduce_while(names, totals, fn name, acc ->
              next = directory_usage(Path.join(path, name), acc)
              if elem(next, 3), do: {:halt, next}, else: {:cont, next}
            end)

          {:error, _reason} ->
            increment_errors(totals)
        end

      {:error, :enoent} ->
        totals

      {:ok, _unsupported} ->
        increment_errors(totals)

      {:error, _reason} ->
        increment_errors(totals)
    end
  end

  defp increment_errors({bytes, files, errors, truncated}),
    do: {bytes, files, errors + 1, truncated}

  defp matching_disk(root, disks) do
    normalized_root = normalize_path(root)

    disks
    |> Enum.map(fn {mount, total_kb, used_percent} ->
      {mount |> List.to_string() |> normalize_path(), total_kb, used_percent}
    end)
    |> Enum.filter(fn {mount, _, _} -> String.starts_with?(normalized_root, mount) end)
    |> Enum.max_by(fn {mount, _, _} -> byte_size(mount) end, fn -> nil end)
  end

  defp normalize_path(path) do
    path
    |> Path.expand()
    |> String.replace("\\", "/")
    |> String.trim_trailing("/")
    |> String.downcase()
  end

  defp safe_check(id, label, callback) do
    callback.() |> Map.merge(%{id: id, label: label})
  rescue
    exception ->
      error("Diagnostic failed unexpectedly.", %{reason: Exception.message(exception)})
      |> Map.merge(%{id: id, label: label})
  catch
    kind, reason ->
      error("Diagnostic failed unexpectedly.", %{reason: inspect({kind, reason})})
      |> Map.merge(%{id: id, label: label})
  end

  defp overall_status(checks) do
    cond do
      Enum.any?(checks, &(&1.status == :error)) -> :error
      Enum.any?(checks, &(&1.status == :warning)) -> :warning
      true -> :ok
    end
  end

  defp public_message(%{id: :active_runtime, status: :ok}),
    do: "Active runtime state is healthy."

  defp public_message(%{id: :active_runtime, status: :warning}),
    do: "Active runtime requires operator attention."

  defp public_message(%{id: :active_runtime, status: :error}),
    do: "The selected Experience runtime is not running."

  defp public_message(%{id: :renderer, status: :ok}),
    do: "Display renderer state is healthy."

  defp public_message(%{id: :renderer, status: :warning}),
    do: "Display renderer requires operator attention."

  defp public_message(%{id: :renderer, status: :error}),
    do: "A display renderer reported a failure."

  defp public_message(check), do: check.message

  defp ok(message, details \\ %{}), do: %{status: :ok, message: message, details: details}

  defp warning(message, details \\ %{}),
    do: %{status: :warning, message: message, details: details}

  defp error(message, details), do: %{status: :error, message: message, details: details}

  defp format_bytes(bytes) when bytes >= 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"

  defp format_bytes(bytes) when bytes >= 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes), do: "#{bytes} bytes"
end
