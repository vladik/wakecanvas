defmodule WakeCanvas.Experiences.PackageSmoke do
  @moduledoc """
  Loads a validated Experience archive in a temporary code path and verifies the
  compiled contract without installing or starting the Experience.

  Run this in a clean platform release process so dependency and module-loading
  failures match the target kiosk.
  """

  alias WakeCanvas.Experiences.{PackageArchive, Registry}

  def verify(archive_path) when is_binary(archive_path) do
    with {:ok, package} <- PackageArchive.validate(archive_path) do
      verify_package(package)
    end
  end

  defp verify_package(package) do
    manifest = package.manifest
    application = String.to_atom(manifest["otpApplication"])
    entry_module = Module.concat([manifest["entryModule"]])
    root = temporary_root()
    ebin = Path.join(root, application_path(manifest, "ebin"))
    initially_loaded = loaded_package_modules(package.files)
    application_was_loaded = not is_nil(Application.spec(application))

    try do
      with :ok <- materialize(root, package.files),
           true <- Code.prepend_path(String.to_charlist(ebin)),
           :ok <- load_application(application),
           :ok <- verify_runtime_applications(application),
           :ok <- load_beam_modules(package.files),
           true <- Code.ensure_loaded?(entry_module),
           {:ok, definition} <- Registry.validate_entry_module(entry_module, manifest) do
        {:ok,
         %{
           digest: package.digest,
           experience_id: definition.id,
           name: definition.name,
           version: definition.version,
           otp_application: application,
           modules: MapSet.size(PackageArchive.beam_modules(package.files))
         }}
      else
        false -> {:error, :entry_module_not_loadable}
        error -> error
      end
    after
      Code.delete_path(String.to_charlist(ebin))
      unload_package_modules(package.files, initially_loaded)
      if not application_was_loaded, do: Application.unload(application)
      File.rm_rf(root)
    end
  end

  defp materialize(root, files) do
    Enum.reduce_while(files, :ok, fn {relative, bytes}, :ok ->
      target = Path.join(root, relative)

      with :ok <- File.mkdir_p(Path.dirname(target)),
           :ok <- File.write(target, bytes, [:binary, :exclusive]) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:smoke_materialization_failed, reason}}}
      end
    end)
  end

  defp load_application(application) do
    case Application.load(application) do
      :ok -> :ok
      {:error, {:already_loaded, ^application}} -> :ok
      {:error, reason} -> {:error, {:application_load_failed, reason}}
    end
  end

  defp verify_runtime_applications(application) do
    application
    |> Application.spec(:applications)
    |> List.wrap()
    |> Enum.reduce_while(:ok, fn dependency, :ok ->
      case Application.load(dependency) do
        :ok -> {:cont, :ok}
        {:error, {:already_loaded, ^dependency}} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:runtime_dependency_missing, dependency, reason}}}
      end
    end)
  end

  defp load_beam_modules(files) do
    files
    |> Enum.filter(fn {path, _bytes} -> String.ends_with?(path, ".beam") end)
    |> Enum.reduce_while(:ok, fn {path, _bytes}, :ok ->
      module = path |> Path.basename(".beam") |> String.to_atom()

      if Code.ensure_loaded?(module),
        do: {:cont, :ok},
        else: {:halt, {:error, {:module_not_loadable, module}}}
    end)
  end

  defp loaded_package_modules(files) do
    files
    |> PackageArchive.beam_modules()
    |> Enum.filter(fn name -> :code.is_loaded(String.to_atom(name)) != false end)
    |> MapSet.new()
  end

  defp unload_package_modules(files, initially_loaded) do
    files
    |> PackageArchive.beam_modules()
    |> MapSet.difference(initially_loaded)
    |> Enum.each(fn name ->
      module = String.to_atom(name)
      :code.purge(module)
      :code.delete(module)
    end)
  end

  defp application_path(manifest, child) do
    "lib/#{manifest["otpApplication"]}-#{manifest["version"]}/#{child}"
  end

  defp temporary_root do
    Path.join(
      System.tmp_dir!(),
      "wakecanvas-package-smoke-#{System.unique_integer([:positive, :monotonic])}"
    )
  end
end
