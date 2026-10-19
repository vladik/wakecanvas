defmodule WakeCanvas.ExperienceSDK.PackageBuilder do
  @moduledoc """
  Builds deterministic `.wakecanvas` archives from a compiled Experience OTP app.

  Archives use uncompressed ZIP entries with fixed timestamps. Identical manifest,
  BEAM, and `priv/` inputs therefore produce identical bytes and checksums.
  """

  @manifest "wakecanvas-experience.json"

  def build(manifest_path, app_path, output_path) do
    with {:ok, manifest_bytes} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(manifest_bytes),
         :ok <- validate_manifest(manifest),
         {:ok, app_files} <- collect_app_files(app_path, manifest),
         files <- [{@manifest, manifest_bytes} | app_files] |> Enum.sort_by(&elem(&1, 0)),
         checksums <- checksums(files),
         archive <- zip(files ++ [{"CHECKSUMS", checksums}]),
         :ok <- File.mkdir_p(Path.dirname(output_path)),
         :ok <- File.write(output_path, archive) do
      {:ok,
       %{
         path: Path.expand(output_path),
         digest: sha256(archive),
         files: length(files) + 1,
         manifest: manifest
       }}
    end
  end

  defp validate_manifest(%{
         "manifestVersion" => 1,
         "experienceId" => id,
         "version" => version,
         "otpApplication" => application,
         "entryModule" => entry_module
       })
       when is_binary(id) and is_binary(version) and is_binary(application) and
              is_binary(entry_module),
       do: :ok

  defp validate_manifest(_), do: {:error, :invalid_manifest}

  defp collect_app_files(app_path, manifest) do
    app = manifest["otpApplication"]
    version = manifest["version"]
    prefix = "lib/#{app}-#{version}"

    files =
      [Path.join(app_path, "ebin"), Path.join(app_path, "priv")]
      |> Enum.flat_map(&regular_files/1)
      |> Enum.sort()

    if files == [] do
      {:error, :compiled_application_not_found}
    else
      {:ok,
       Enum.map(files, fn source ->
         relative = Path.relative_to(source, app_path) |> normalize_path()
         {"#{prefix}/#{relative}", File.read!(source)}
       end)}
    end
  end

  defp regular_files(root) do
    case File.ls(root) do
      {:ok, names} ->
        Enum.flat_map(names, fn name ->
          path = Path.join(root, name)
          if File.dir?(path), do: regular_files(path), else: [path]
        end)

      {:error, :enoent} ->
        []
    end
  end

  defp checksums(files) do
    Enum.map_join(files, "", fn {path, bytes} -> "#{sha256(bytes)}  #{path}\n" end)
  end

  defp sha256(bytes),
    do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp normalize_path(path), do: String.replace(path, "\\", "/")

  # A deliberately small deterministic ZIP writer. Stored entries are adequate
  # for already-compressed browser/media assets and avoid platform-specific ZIP
  # metadata changing the package digest.
  defp zip(files) do
    {locals, central, offset} =
      Enum.reduce(files, {[], [], 0}, fn {name, data}, {locals, central, offset} ->
        name = :unicode.characters_to_binary(name)
        crc = :erlang.crc32(data)
        size = byte_size(data)

        local =
          <<0x04034B50::little-32, 20::little-16, 0x0800::little-16, 0::little-16, 0::little-16,
            0x21::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name)::little-16, 0::little-16, name::binary, data::binary>>

        directory =
          <<0x02014B50::little-32, 20::little-16, 20::little-16, 0x0800::little-16, 0::little-16,
            0::little-16, 0x21::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name)::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-32, offset::little-32, name::binary>>

        {[local | locals], [directory | central], offset + byte_size(local)}
      end)

    central = central |> Enum.reverse() |> IO.iodata_to_binary()
    count = length(files)

    end_record =
      <<0x06054B50::little-32, 0::little-16, 0::little-16, count::little-16, count::little-16,
        byte_size(central)::little-32, offset::little-32, 0::little-16>>

    IO.iodata_to_binary([Enum.reverse(locals), central, end_record])
  end
end
