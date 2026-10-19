defmodule WakeCanvas.Experiences.PackageArchive do
  @moduledoc """
  Validates and stages trusted-code Experience archives without loading code.

  Validation is performed from ZIP metadata and in-memory entries before any file
  is written. A valid archive is extracted only below its content-addressed cache
  directory.
  """

  @manifest_path "wakecanvas-experience.json"
  @checksums_path "CHECKSUMS"
  @allowed_roots MapSet.new([@manifest_path, @checksums_path, "SIGNATURE", "lib"])
  @max_archive_bytes 128 * 1024 * 1024
  @max_uncompressed_bytes 512 * 1024 * 1024
  @max_file_bytes 128 * 1024 * 1024
  @max_files 5_000

  def validate(path) when is_binary(path) do
    with {:ok, stat} <- File.stat(path),
         :ok <- limit(stat.size, @max_archive_bytes, :archive_too_large),
         {:ok, table} <- zip_table(path),
         {:ok, names} <- validate_table(table),
         {:ok, extracted} <- extract(path),
         {:ok, files} <- normalize_extracted(extracted, names),
         :ok <- verify_checksums(files),
         {:ok, manifest} <- decode_manifest(files),
         :ok <- validate_manifest(manifest, files) do
      {:ok,
       %{
         digest: path |> File.read!() |> sha256(),
         manifest: manifest,
         files: files
       }}
    end
  end

  def stage(path) do
    with {:ok, package} <- validate(path),
         {:ok, cache_path} <- stage_files(package.digest, package.files) do
      {:ok, Map.put(package, :cache_path, cache_path)}
    end
  end

  def validate_cache(digest) when is_binary(digest) do
    root = cache_path(digest)

    with true <- File.dir?(root),
         {:ok, files} <- read_cache_files(root),
         :ok <- limit(map_size(files), @max_files, :too_many_files),
         :ok <-
           limit(
             Enum.reduce(files, 0, fn {_, bytes}, total -> total + byte_size(bytes) end),
             @max_uncompressed_bytes,
             :package_too_large
           ),
         :ok <- Enum.reduce_while(Map.keys(files), :ok, &validate_cached_path/2),
         :ok <- verify_checksums(files),
         {:ok, manifest} <- decode_manifest(files),
         :ok <- validate_manifest(manifest, files) do
      {:ok, %{digest: digest, manifest: manifest, files: files, cache_path: root}}
    else
      false -> {:error, :cache_missing}
      error -> error
    end
  end

  def cache_path(digest) do
    Application.fetch_env!(:wake_canvas, :data_root)
    |> Path.join("packages/cache/sha256-#{digest}")
  end

  def remove_cache(digest) when is_binary(digest) do
    if Regex.match?(~r/^[0-9a-f]{64}$/, digest) do
      case File.rm_rf(cache_path(digest)) do
        {:ok, _removed} -> :ok
        {:error, reason, _path} -> {:error, reason}
      end
    else
      {:error, :invalid_digest}
    end
  end

  def beam_modules(files) when is_map(files) do
    files
    |> Map.keys()
    |> Enum.filter(&Regex.match?(~r{/ebin/[^/]+\.beam$}, &1))
    |> Enum.map(&Path.basename(&1, ".beam"))
    |> MapSet.new()
  end

  def cached_beam_modules(digest) when is_binary(digest) do
    digest
    |> cache_path()
    |> Path.join("lib")
    |> child_directories()
    |> Enum.flat_map(fn app_dir ->
      case File.ls(Path.join(app_dir, "ebin")) do
        {:ok, names} ->
          names
          |> Enum.filter(&String.ends_with?(&1, ".beam"))
          |> Enum.map(&Path.basename(&1, ".beam"))

        {:error, _} ->
          []
      end
    end)
    |> MapSet.new()
  end

  defp zip_table(path) do
    case :zip.list_dir(String.to_charlist(path)) do
      {:ok, table} -> {:ok, table}
      {:error, reason} -> {:error, {:invalid_archive, reason}}
    end
  end

  defp validate_table(table) do
    entries = Enum.reject(table, &(elem(&1, 0) == :zip_comment))

    with :ok <- limit(length(entries), @max_files, :too_many_files),
         {:ok, metadata} <- Enum.reduce_while(entries, {:ok, []}, &validate_entry/2),
         names = Enum.map(metadata, &elem(&1, 0)),
         :ok <- ensure_unique(names),
         :ok <- ensure_required(names) do
      {:ok, MapSet.new(names)}
    end
  end

  defp validate_entry({:zip_file, raw_name, info, _, _, _}, {:ok, entries}) do
    size = elem(info, 1)
    type = elem(info, 2)
    name = raw_name |> List.to_string() |> normalize_path() |> normalize_directory(type)

    with :ok <- safe_path(name),
         :ok <- valid_type(type, name),
         :ok <- limit(size, @max_file_bytes, {:file_too_large, name}),
         :ok <- allowed_root(name),
         :ok <-
           limit(
             Enum.reduce(entries, size, fn {_, bytes}, total -> total + bytes end),
             @max_uncompressed_bytes,
             :package_too_large
           ) do
      {:cont, {:ok, [{name, size} | entries]}}
    else
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp validate_entry(_, _), do: {:halt, {:error, :invalid_zip_entry}}

  defp safe_path(name) do
    segments = String.split(name, "/", trim: false)

    cond do
      name == "" -> {:error, :empty_path}
      String.contains?(name, ["\\", <<0>>]) -> {:error, {:unsafe_path, name}}
      String.starts_with?(name, "/") -> {:error, {:unsafe_path, name}}
      Regex.match?(~r/^[A-Za-z]:/, name) -> {:error, {:unsafe_path, name}}
      Enum.any?(segments, &(&1 in ["", ".", ".."])) -> {:error, {:unsafe_path, name}}
      true -> :ok
    end
  end

  defp valid_type(:regular, _name), do: :ok
  defp valid_type(:directory, name) when is_binary(name), do: :ok
  defp valid_type(_, name), do: {:error, {:unsupported_file_type, name}}

  defp allowed_root(name) do
    if name |> String.split("/", parts: 2) |> hd() |> then(&MapSet.member?(@allowed_roots, &1)),
      do: :ok,
      else: {:error, {:unexpected_top_level_path, name}}
  end

  defp ensure_unique(names) do
    if length(names) == MapSet.size(MapSet.new(names)),
      do: :ok,
      else: {:error, :duplicate_path}
  end

  defp ensure_required(names) do
    if @manifest_path in names and @checksums_path in names,
      do: :ok,
      else: {:error, :required_files_missing}
  end

  defp extract(path) do
    case :zip.extract(String.to_charlist(path), [:memory]) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:invalid_archive, reason}}
    end
  end

  defp normalize_extracted(entries, expected_names) do
    files =
      entries
      |> Enum.map(fn {name, bytes} -> {name |> List.to_string() |> normalize_path(), bytes} end)
      |> Enum.reject(fn {name, _} -> String.ends_with?(name, "/") end)
      |> Map.new()

    if MapSet.subset?(MapSet.new(Map.keys(files)), expected_names),
      do: {:ok, files},
      else: {:error, :archive_entries_changed}
  end

  defp verify_checksums(files) do
    expected_paths =
      files |> Map.keys() |> Enum.reject(&(&1 in [@checksums_path, "SIGNATURE"])) |> MapSet.new()

    with {:ok, checksum_bytes} <- Map.fetch(files, @checksums_path),
         {:ok, declared} <- parse_checksums(checksum_bytes),
         true <- MapSet.new(Map.keys(declared)) == expected_paths,
         true <- Enum.all?(declared, fn {path, digest} -> sha256(files[path]) == digest end) do
      :ok
    else
      false -> {:error, :checksum_mismatch}
      :error -> {:error, :checksums_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_checksums(bytes) do
    bytes
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn line, {:ok, checksums} ->
      case String.split(line, "  ", parts: 2) do
        [digest, path] ->
          path = normalize_path(path)

          if Regex.match?(~r/^[0-9a-f]{64}$/, digest) and not Map.has_key?(checksums, path) do
            {:cont, {:ok, Map.put(checksums, path, digest)}}
          else
            {:halt, {:error, :invalid_checksums}}
          end

        _ ->
          {:halt, {:error, :invalid_checksums}}
      end
    end)
  end

  defp decode_manifest(files) do
    with {:ok, bytes} <- Map.fetch(files, @manifest_path),
         {:ok, manifest} <- Jason.decode(bytes) do
      {:ok, manifest}
    else
      :error -> {:error, :manifest_missing}
      {:error, _} -> {:error, :invalid_manifest_json}
    end
  end

  defp validate_manifest(manifest, files) do
    with :ok <- required_manifest_fields(manifest),
         :ok <- valid_manifest_names(manifest),
         :ok <- valid_versions(manifest),
         :ok <- compatible(manifest),
         :ok <- expected_application_files(manifest, files),
         :ok <- validate_beam_files(manifest, files),
         :ok <- validate_application_spec(manifest, files),
         :ok <- validate_surfaces(manifest, files),
         :ok <- validate_variants(manifest, files),
         :ok <- validate_browser_assets(manifest, files),
         :ok <- validate_native_target(manifest, files) do
      :ok
    end
  end

  defp required_manifest_fields(%{
         "manifestVersion" => 1,
         "experienceId" => id,
         "name" => name,
         "version" => version,
         "otpApplication" => app,
         "entryModule" => entry,
         "sdkRequirement" => sdk,
         "platformRequirement" => platform,
         "elixirRequirement" => elixir,
         "otpRequirement" => otp,
         "target" => target,
         "surfaces" => surfaces,
         "displayVariants" => variants
       })
       when is_binary(id) and is_binary(name) and is_binary(version) and is_binary(app) and
              is_binary(entry) and is_binary(sdk) and is_binary(platform) and is_binary(elixir) and
              is_binary(otp) and is_binary(target) and is_list(surfaces) and is_list(variants),
       do: :ok

  defp required_manifest_fields(_), do: {:error, :invalid_manifest}

  defp valid_manifest_names(manifest) do
    valid =
      Regex.match?(~r/^[a-z0-9]+(?:[._-][a-z0-9]+)+$/, manifest["experienceId"]) and
        Regex.match?(~r/^[a-z][a-z0-9_]*$/, manifest["otpApplication"]) and
        Regex.match?(~r/^[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*$/, manifest["entryModule"])

    if valid, do: :ok, else: {:error, :invalid_manifest_identifier}
  end

  defp valid_versions(manifest) do
    requirements = ~w(sdkRequirement platformRequirement elixirRequirement otpRequirement)

    if match?({:ok, _}, Version.parse(manifest["version"])) and
         Enum.all?(requirements, &match?({:ok, _}, Version.parse_requirement(manifest[&1]))),
       do: :ok,
       else: {:error, :invalid_version_requirement}
  end

  defp compatible(manifest) do
    checks = [
      {"sdk", WakeCanvas.ExperienceSDK.version(), manifest["sdkRequirement"]},
      {"platform", platform_version(), manifest["platformRequirement"]},
      {"Elixir", System.version(), manifest["elixirRequirement"]},
      {"OTP", normalize_otp(System.otp_release()), manifest["otpRequirement"]}
    ]

    case Enum.find(checks, fn {_, version, requirement} ->
           not Version.match?(version, requirement)
         end) do
      nil -> compatible_target(manifest["target"])
      {name, version, requirement} -> {:error, {:incompatible, name, version, requirement}}
    end
  end

  defp compatible_target("any"), do: :ok

  defp compatible_target(target) do
    current = Application.get_env(:wake_canvas, :package_target, current_target())
    if target == current, do: :ok, else: {:error, {:incompatible_target, current, target}}
  end

  defp current_target do
    os =
      if match?({:win32, _}, :os.type()), do: "windows", else: elem(:os.type(), 1) |> to_string()

    arch =
      :erlang.system_info(:system_architecture)
      |> List.to_string()
      |> String.split("-", parts: 2)
      |> hd()
      |> case do
        "amd64" -> "x86_64"
        "arm64" -> "aarch64"
        value -> value
      end

    "#{os}-#{arch}"
  end

  defp expected_application_files(manifest, files) do
    prefix = "lib/#{manifest["otpApplication"]}-#{manifest["version"]}"
    app_file = "#{prefix}/ebin/#{manifest["otpApplication"]}.app"
    entry_beam = "#{prefix}/ebin/Elixir.#{manifest["entryModule"]}.beam"

    unexpected_library_file =
      files
      |> Map.keys()
      |> Enum.find(fn path ->
        String.starts_with?(path, "lib/") and not String.starts_with?(path, prefix <> "/")
      end)

    cond do
      unexpected_library_file ->
        {:error, {:unexpected_application_path, unexpected_library_file}}

      not Map.has_key?(files, app_file) ->
        {:error, {:application_file_missing, app_file}}

      not Map.has_key?(files, entry_beam) ->
        {:error, {:entry_module_missing, manifest["entryModule"]}}

      true ->
        :ok
    end
  end

  defp validate_beam_files(manifest, files) do
    prefix = "lib/#{manifest["otpApplication"]}-#{manifest["version"]}/ebin/"

    files
    |> Enum.filter(fn {path, _} ->
      String.starts_with?(path, prefix) and String.ends_with?(path, ".beam")
    end)
    |> Enum.reduce_while(:ok, fn {path, bytes}, :ok ->
      expected = Path.basename(path, ".beam")

      try do
        case :beam_lib.info(bytes) |> Keyword.fetch(:module) do
          {:ok, module} when is_atom(module) ->
            if Atom.to_string(module) == expected,
              do: {:cont, :ok},
              else: {:halt, {:error, {:beam_module_mismatch, path}}}

          _ ->
            {:halt, {:error, {:invalid_beam, path}}}
        end
      catch
        _, _ -> {:halt, {:error, {:invalid_beam, path}}}
      end
    end)
  end

  defp validate_application_spec(manifest, files) do
    prefix = "lib/#{manifest["otpApplication"]}-#{manifest["version"]}"
    path = "#{prefix}/ebin/#{manifest["otpApplication"]}.app"

    with {:ok, tokens, _} <- :erl_scan.string(files[path] |> String.to_charlist()),
         {:ok, {:application, application, properties}} <- :erl_parse.parse_term(tokens),
         true <- Atom.to_string(application) == manifest["otpApplication"],
         version when is_list(version) or is_binary(version) <- Keyword.get(properties, :vsn),
         true <- to_string(version) == manifest["version"] do
      :ok
    else
      _ -> {:error, :invalid_application_spec}
    end
  end

  defp validate_surfaces(manifest, files) do
    surfaces = manifest["surfaces"]
    ids = Enum.map(surfaces, &Map.get(&1, "id"))
    paths = Enum.map(surfaces, &Map.get(&1, "path"))

    with true <- surfaces != [],
         true <- unique?(ids) and unique?(paths),
         true <- Enum.all?(surfaces, &valid_surface?/1),
         nil <- Enum.find(surfaces, &(not module_present?(manifest, files, &1["module"]))) do
      :ok
    else
      false -> {:error, :invalid_surfaces}
      %{"module" => module} -> {:error, {:surface_module_missing, module}}
      _ -> {:error, :invalid_surfaces}
    end
  end

  defp valid_surface?(%{"id" => id, "path" => path, "module" => module, "role" => role}) do
    is_binary(id) and Regex.match?(~r/^[a-z][a-z0-9_-]*$/, id) and
      is_binary(path) and Regex.match?(~r/^[a-z][a-z0-9-]*$/, path) and
      is_binary(module) and Regex.match?(~r/^[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*$/, module) and
      role in ["display", "primary-intake", "participant", "operator"]
  end

  defp valid_surface?(_), do: false

  defp validate_variants(manifest, files) do
    variants = manifest["displayVariants"]
    ids = Enum.map(variants, &Map.get(&1, "id"))
    default = manifest["defaultDisplayVariant"]

    with true <- unique?(ids),
         true <- Enum.all?(variants, &valid_variant?/1),
         true <- (variants == [] and is_nil(default)) or default in ids,
         :ok <- validate_variant_assets(manifest, files, variants),
         :ok <- validate_variant_fallbacks(variants, ids),
         :ok <- validate_variant_thumbnails(manifest, files, variants) do
      :ok
    else
      false -> {:error, :invalid_display_variants}
      {:error, _reason} = error -> error
    end
  end

  defp validate_variant_assets(manifest, files, variants) do
    case Enum.find(variants, &(not asset_present?(manifest, files, &1["entrypoint"]))) do
      nil -> :ok
      variant -> {:error, {:renderer_asset_missing, variant["entrypoint"]}}
    end
  end

  defp validate_variant_fallbacks(variants, ids) do
    case Enum.find(variants, fn variant ->
           variant["fallback"] && variant["fallback"] not in ids
         end) do
      nil -> :ok
      variant -> {:error, {:variant_fallback_missing, variant["fallback"]}}
    end
  end

  defp validate_variant_thumbnails(manifest, files, variants) do
    case Enum.find(variants, fn variant ->
           variant["thumbnail"] && not asset_present?(manifest, files, variant["thumbnail"])
         end) do
      nil -> :ok
      variant -> {:error, {:thumbnail_asset_missing, variant["thumbnail"]}}
    end
  end

  defp valid_variant?(%{"id" => id, "label" => label, "entrypoint" => entrypoint} = variant) do
    capabilities = Map.get(variant, "capabilities", [])

    is_binary(id) and Regex.match?(~r/^[a-z][a-z0-9-]*$/, id) and is_binary(label) and
      valid_asset_path?(entrypoint) and is_list(capabilities) and
      Enum.all?(capabilities, &is_binary/1)
  end

  defp valid_variant?(_), do: false

  defp validate_browser_assets(manifest, files) do
    stylesheet = get_in(manifest, ["browser", "stylesheet"])

    cond do
      is_nil(stylesheet) ->
        :ok

      not valid_asset_path?(stylesheet) ->
        {:error, :invalid_stylesheet_path}

      not asset_present?(manifest, files, stylesheet) ->
        {:error, {:stylesheet_missing, stylesheet}}

      true ->
        :ok
    end
  end

  defp validate_native_target(%{"target" => "any"} = manifest, files) do
    prefix = "lib/#{manifest["otpApplication"]}-#{manifest["version"]}/priv/native/"

    if Enum.any?(Map.keys(files), &String.starts_with?(&1, prefix)),
      do: {:error, :native_files_require_specific_target},
      else: :ok
  end

  defp validate_native_target(_manifest, _files), do: :ok

  defp module_present?(manifest, files, module) do
    path =
      "lib/#{manifest["otpApplication"]}-#{manifest["version"]}/ebin/Elixir.#{module}.beam"

    Map.has_key?(files, path)
  end

  defp asset_present?(manifest, files, relative) do
    valid_asset_path?(relative) and
      Map.has_key?(
        files,
        "lib/#{manifest["otpApplication"]}-#{manifest["version"]}/priv/#{relative}"
      )
  end

  defp valid_asset_path?(path) when is_binary(path) do
    String.starts_with?(path, "static/") and safe_path(path) == :ok
  end

  defp valid_asset_path?(_), do: false

  defp unique?(values),
    do: Enum.all?(values, &is_binary/1) and length(values) == MapSet.size(MapSet.new(values))

  defp stage_files(digest, files) do
    destination = cache_path(digest)

    if File.dir?(destination) do
      case validate_cache(digest) do
        {:ok, _} -> {:ok, destination}
        {:error, reason} -> {:error, {:cache_invalid, reason}}
      end
    else
      temporary = destination <> ".staging-#{System.unique_integer([:positive])}"

      try do
        Enum.each(files, fn {relative, bytes} ->
          target = Path.join(temporary, relative)
          File.mkdir_p!(Path.dirname(target))
          File.write!(target, bytes, [:binary, :exclusive])
        end)

        case File.rename(temporary, destination) do
          :ok -> {:ok, destination}
          {:error, :eexist} -> File.rm_rf!(temporary) && {:ok, destination}
          {:error, reason} -> {:error, {:stage_failed, reason}}
        end
      rescue
        error -> {:error, {:stage_failed, Exception.message(error)}}
      after
        if File.exists?(temporary), do: File.rm_rf!(temporary)
      end
    end
  end

  defp read_cache_files(root), do: read_cache_directory(root, root, %{})

  defp read_cache_directory(root, directory, files) do
    with {:ok, names} <- File.ls(directory) do
      Enum.reduce_while(names, {:ok, files}, fn name, {:ok, accumulator} ->
        path = Path.join(directory, name)

        case File.lstat(path) do
          {:ok, %{type: :directory}} ->
            case read_cache_directory(root, path, accumulator) do
              {:ok, nested} -> {:cont, {:ok, nested}}
              error -> {:halt, error}
            end

          {:ok, %{type: :regular, size: size}} when size <= @max_file_bytes ->
            relative = path |> Path.relative_to(root) |> normalize_path()

            case File.read(path) do
              {:ok, bytes} -> {:cont, {:ok, Map.put(accumulator, relative, bytes)}}
              {:error, reason} -> {:halt, {:error, {:cache_read_failed, reason}}}
            end

          {:ok, %{type: :regular}} ->
            {:halt, {:error, :file_too_large}}

          {:ok, _} ->
            {:halt, {:error, :cache_contains_link_or_special_file}}

          {:error, reason} ->
            {:halt, {:error, {:cache_read_failed, reason}}}
        end
      end)
    else
      {:error, reason} -> {:error, {:cache_read_failed, reason}}
    end
  end

  defp validate_cached_path(path, :ok) do
    with :ok <- safe_path(path),
         :ok <- allowed_root(path),
         do: {:cont, :ok},
         else: (error -> {:halt, error})
  end

  defp platform_version do
    case Application.spec(:wake_canvas, :vsn) do
      nil -> "0.1.0"
      version -> List.to_string(version)
    end
  end

  defp normalize_otp(version) do
    if String.contains?(version, "."), do: version, else: version <> ".0.0"
  end

  defp normalize_path(path), do: String.replace(path, "\\", "/")
  defp normalize_directory(path, :directory), do: String.trim_trailing(path, "/")
  defp normalize_directory(path, _type), do: path

  defp child_directories(root) do
    case File.ls(root) do
      {:ok, names} -> names |> Enum.map(&Path.join(root, &1)) |> Enum.filter(&File.dir?/1)
      {:error, _} -> []
    end
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp limit(value, maximum, _reason) when value <= maximum, do: :ok
  defp limit(_value, _maximum, reason), do: {:error, reason}
end
