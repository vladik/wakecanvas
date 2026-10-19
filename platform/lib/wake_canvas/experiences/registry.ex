defmodule WakeCanvas.Experiences.Registry do
  use GenServer

  alias WakeCanvas.ExperienceSDK.Definition
  alias WakeCanvas.Experiences.{Package, PackageArchive}
  alias WakeCanvas.Repo

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def definition(experience_id), do: GenServer.call(__MODULE__, {:definition, experience_id})
  def entry_module(experience_id), do: GenServer.call(__MODULE__, {:entry_module, experience_id})

  def surface(experience_id, path) do
    with {:ok, definition} <- definition(experience_id),
         surface when not is_nil(surface) <-
           Enum.find(definition.surfaces, &(&1.path == path)),
         true <- Code.ensure_loaded?(surface.module) do
      {:ok, surface}
    else
      nil -> {:error, :unknown_surface}
      false -> {:error, :surface_not_loaded}
      error -> error
    end
  end

  def display_variant(experience_id, requested_id \\ nil) do
    with {:ok, definition} <- definition(experience_id) do
      case definition.display_variants do
        [] ->
          {:ok, nil}

        variants ->
          id = requested_id || definition.default_display_variant

          case Enum.find(variants, &(&1.id == id)) do
            nil -> {:error, :unknown_display_variant}
            variant -> {:ok, variant}
          end
      end
    end
  end

  @impl true
  def init(:ok) do
    definitions =
      :wake_canvas
      |> Application.get_env(:development_experiences, [])
      |> Enum.reduce(%{}, &load_definition/2)
      |> load_installed_packages()

    {:ok, definitions}
  end

  @impl true
  def handle_call({:definition, experience_id}, _from, definitions) do
    case Map.fetch(definitions, experience_id) do
      {:ok, %{definition: definition}} -> {:reply, {:ok, definition}, definitions}
      :error -> {:reply, {:error, :experience_not_loaded}, definitions}
    end
  end

  def handle_call({:entry_module, experience_id}, _from, definitions) do
    case Map.fetch(definitions, experience_id) do
      {:ok, %{entry_module: module}} -> {:reply, {:ok, module}, definitions}
      :error -> {:reply, {:error, :experience_not_loaded}, definitions}
    end
  end

  defp load_definition(%{ebin: ebin, entry_module: entry_module} = registration, definitions) do
    _ = Code.append_path(String.to_charlist(ebin))
    module = Module.concat([entry_module])

    with true <- Code.ensure_loaded?(module),
         {:ok, %Definition{} = definition} <- safe_definition(module),
         :ok <- maybe_register_development_package(definition, registration) do
      Map.put(definitions, definition.id, %{definition: definition, entry_module: module})
    else
      _ -> definitions
    end
  end

  defp maybe_register_development_package(definition, %{register_in_catalog: true}) do
    case WakeCanvas.Experiences.register_development_package(definition) do
      {:ok, _package} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_register_development_package(_definition, _registration), do: :ok

  defp load_installed_packages(definitions) do
    Package
    |> Repo.all()
    |> Enum.filter(&is_binary(&1.archive_digest))
    |> Enum.reduce(definitions, fn package, loaded ->
      if Map.has_key?(loaded, package.id) do
        # Source-linked code is authoritative in development/test. A release has
        # no development registrations and therefore always loads the cache.
        mark_status(package, "installed", nil)
        loaded
      else
        load_installed_package(package, loaded)
      end
    end)
  end

  defp load_installed_package(package, definitions) do
    manifest = package.manifest
    app = manifest["otpApplication"]
    version = manifest["version"]
    entry_module = manifest["entryModule"]

    ebin =
      package.archive_digest
      |> PackageArchive.cache_path()
      |> Path.join("lib/#{app}-#{version}/ebin")

    result =
      with {:ok, validated} <- PackageArchive.validate_cache(package.archive_digest),
           true <- validated.manifest == manifest,
           true <- File.dir?(ebin),
           true <- Code.append_path(String.to_charlist(ebin)),
           application <- String.to_atom(app),
           load_result when load_result in [:ok, {:error, {:already_loaded, application}}] <-
             Application.load(application),
           module <- Module.concat([entry_module]),
           {:module, ^module} <- :code.load_file(module),
           {:ok, definition} <- validate_entry_module(module, manifest) do
        {:ok, %{definition: definition, entry_module: module}}
      else
        reason -> {:error, reason}
      end

    case result do
      {:ok, loaded} ->
        mark_status(package, "installed", nil)
        Map.put(definitions, package.id, loaded)

      {:error, reason} ->
        mark_status(package, "rejected", diagnostic(reason))
        definitions
    end
  end

  defp mark_status(%Package{status: status, diagnostic: diagnostic}, status, diagnostic), do: :ok

  defp mark_status(package, status, diagnostic) do
    package
    |> Ecto.Changeset.change(status: status, diagnostic: diagnostic)
    |> Repo.update()

    :ok
  end

  defp diagnostic(reason) do
    reason
    |> inspect(limit: 12, printable_limit: 300)
    |> String.slice(0, 500)
  end

  @doc false
  def validate_entry_module(module, manifest) when is_atom(module) and is_map(manifest) do
    with true <- function_exported?(module, :definition, 0),
         true <- function_exported?(module, :validate_config, 1),
         {:ok, %Definition{} = definition} <- safe_definition(module),
         :ok <- validate_definition(definition, manifest) do
      {:ok, definition}
    else
      false -> {:error, :entry_contract_missing}
      error -> error
    end
  end

  defp safe_definition(module) do
    try do
      {:ok, module.definition()}
    rescue
      error -> {:error, {:definition_exception, Exception.message(error)}}
    catch
      kind, reason -> {:error, {:definition_failure, kind, reason}}
    end
  end

  @doc false
  def validate_definition(%Definition{} = definition, manifest) do
    compiled_surfaces =
      Enum.map(definition.surfaces, fn surface ->
        %{
          "id" => normalize_identifier(Map.get(surface, :id)),
          "path" => Map.get(surface, :path),
          "module" =>
            surface |> Map.get(:module) |> Atom.to_string() |> String.trim_leading("Elixir."),
          "role" => normalize_identifier(Map.get(surface, :role))
        }
      end)

    compiled_variants =
      Enum.map(definition.display_variants, fn variant ->
        %{
          "id" => Map.get(variant, :id),
          "entrypoint" => Map.get(variant, :entrypoint),
          "thumbnail" => Map.get(variant, :thumbnail),
          "capabilities" =>
            Enum.map(Map.get(variant, :capabilities, []), &normalize_identifier/1),
          "fallback" => Map.get(variant, :fallback)
        }
      end)

    manifest_surfaces =
      Enum.map(manifest["surfaces"], &Map.take(&1, ["id", "path", "module", "role"]))

    manifest_variants =
      Enum.map(manifest["displayVariants"], fn variant ->
        %{
          "id" => variant["id"],
          "entrypoint" => variant["entrypoint"],
          "thumbnail" => variant["thumbnail"],
          "capabilities" => Map.get(variant, "capabilities", []),
          "fallback" => variant["fallback"]
        }
      end)

    checks = [
      {definition.id, manifest["experienceId"], :experience_id},
      {definition.name, manifest["name"], :name},
      {definition.version, manifest["version"], :version},
      {Atom.to_string(definition.otp_application), manifest["otpApplication"], :otp_application},
      {Map.get(definition, :stylesheet), get_in(manifest, ["browser", "stylesheet"]),
       :stylesheet},
      {definition.default_display_variant, manifest["defaultDisplayVariant"], :default_variant},
      {Enum.map(definition.capabilities, &normalize_identifier/1) |> Enum.sort(),
       Map.get(manifest, "capabilities", []) |> Enum.sort(), :capabilities},
      {Enum.sort_by(compiled_surfaces, & &1["id"]), Enum.sort_by(manifest_surfaces, & &1["id"]),
       :surfaces},
      {Enum.sort_by(compiled_variants, & &1["id"]), Enum.sort_by(manifest_variants, & &1["id"]),
       :display_variants}
    ]

    case Enum.find(checks, fn {compiled, declared, _field} -> compiled != declared end) do
      nil -> :ok
      {_compiled, _declared, field} -> {:error, {:definition_manifest_mismatch, field}}
    end
  end

  defp normalize_identifier(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", "-")

  defp normalize_identifier(value), do: value
end
