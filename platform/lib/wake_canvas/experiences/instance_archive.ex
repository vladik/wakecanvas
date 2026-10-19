defmodule WakeCanvas.Experiences.InstanceArchive do
  @moduledoc """
  Builds and validates portable, self-contained Experience instance archives.

  The platform treats the Experience-owned files as opaque bytes. It never opens
  the instance database; requiring an archived instance gives the Experience a
  stable point at which those bytes can be copied safely.
  """

  alias WakeCanvas.Experiences.{Instance, InstancePaths}

  @manifest "wakecanvas-instance.json"
  @checksums "CHECKSUMS"
  @format_version 1
  @max_files 60_000
  @max_archive_size 2 * 1024 * 1024 * 1024
  @max_file_size 2 * 1024 * 1024 * 1024
  @max_total_size 2 * 1024 * 1024 * 1024

  def export(%Instance{archived_at: nil}), do: {:error, :not_archived}

  def export(%Instance{} = instance) do
    source = InstancePaths.data_dir(instance.id)
    export_root = Path.join(data_root(), "exports")
    File.mkdir_p!(source)
    File.mkdir_p!(export_root)

    output =
      Path.join(
        export_root,
        "#{instance.id}-#{System.unique_integer([:positive])}.wakecanvas-instance"
      )

    with {:ok, files} <- regular_files(source),
         {:ok, manifest} <- manifest(instance),
         {:ok, checksums} <- checksums(source, manifest, files),
         {:ok, _} <- create_zip(output, source, manifest, checksums, files) do
      {:ok, %{path: output, filename: "#{safe_filename(instance.name)}.wakecanvas-instance"}}
    else
      error ->
        _ = File.rm(output)
        error
    end
  end

  def stage(path) when is_binary(path) do
    work =
      Path.join([data_root(), "importing", Integer.to_string(System.unique_integer([:positive]))])

    content = Path.join(work, "content")

    with {:ok, stat} <- File.stat(path),
         true <- stat.size <= @max_archive_size || {:error, :archive_too_large},
         {:ok, entries} <- list_and_validate(path),
         :ok <- File.mkdir_p(content),
         {:ok, _} <- extract(path, content),
         {:ok, manifest} <- validate_extracted(content, entries),
         :ok <- remove_control_files(content) do
      {:ok, %{work_dir: work, content_dir: content, manifest: manifest}}
    else
      error ->
        _ = File.rm_rf(work)
        error
    end
  end

  def cleanup(%{work_dir: work}), do: File.rm_rf(work)

  defp manifest(instance) do
    payload = %{
      "formatVersion" => @format_version,
      "exportedAt" => DateTime.utc_now() |> DateTime.truncate(:second),
      "instance" => %{
        "id" => instance.id,
        "experienceId" => instance.experience_id,
        "experienceVersion" => instance.package.version,
        "name" => instance.name,
        "slug" => instance.slug,
        "config" => instance.config,
        "participantCodeDigest" => instance.participant_code_digest,
        "participantCodeVersion" => instance.participant_code_version
      }
    }

    {:ok, Jason.encode_to_iodata!(payload, pretty: true) |> IO.iodata_to_binary()}
  rescue
    _ -> {:error, :invalid_instance_metadata}
  end

  defp regular_files(root) do
    root
    |> walk("")
    |> Enum.reduce_while({:ok, []}, fn
      {:file, relative}, {:ok, files} when relative not in [@manifest, @checksums] ->
        {:cont, {:ok, [relative | files]}}

      {:file, relative}, _ ->
        {:halt, {:error, {:reserved_path, relative}}}

      {:directory, _}, acc ->
        {:cont, acc}

      {:unsupported, relative}, _ ->
        {:halt, {:error, {:unsupported_file, relative}}}
    end)
    |> case do
      {:ok, files} -> {:ok, Enum.sort(files)}
      error -> error
    end
  end

  defp walk(root, relative) do
    path = if relative == "", do: root, else: Path.join(root, relative)

    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        path
        |> File.ls!()
        |> Enum.sort()
        |> Enum.flat_map(&walk(root, Path.join(relative, &1)))

      {:ok, %{type: :regular}} ->
        [{:file, Path.split(relative) |> Enum.join("/")}]

      {:ok, _} ->
        [{:unsupported, relative}]

      {:error, _} ->
        [{:unsupported, relative}]
    end
  end

  defp checksums(root, manifest, files) do
    lines =
      [{sha256(manifest), @manifest}] ++
        Enum.map(files, fn relative -> {sha256_file!(Path.join(root, relative)), relative} end)

    {:ok, Enum.map_join(lines, "", fn {digest, name} -> "#{digest}  #{name}\n" end)}
  rescue
    _ -> {:error, :checksum_failed}
  end

  defp create_zip(output, source, manifest, checksums, files) do
    entries =
      [
        {@manifest, {:binary, manifest}},
        {@checksums, {:binary, checksums}}
      ] ++ Enum.map(files, &{&1, {:file, Path.join(source, &1)}})

    case File.open(output, [:write, :binary], fn device -> write_zip(device, entries) end) do
      {:ok, :ok} -> {:ok, output}
      {:ok, {:error, reason}} -> {:error, {:archive_write_failed, reason}}
      {:error, reason} -> {:error, {:archive_write_failed, reason}}
    end
  rescue
    error -> {:error, {:archive_write_failed, Exception.message(error)}}
  end

  # Stored ZIP entries keep already-compressed media unchanged. This writer
  # streams files instead of loading a workshop's complete media library into
  # the BEAM heap.
  defp write_zip(device, entries) do
    {directories, offset} =
      Enum.reduce(entries, {[], 0}, fn {name, source}, {directories, offset} ->
        name = :unicode.characters_to_binary(name)
        {size, crc} = zip_source_info(source)

        local =
          <<0x04034B50::little-32, 20::little-16, 0x0800::little-16, 0::little-16, 0::little-16,
            0x21::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name)::little-16, 0::little-16, name::binary>>

        :ok = IO.binwrite(device, local)
        :ok = write_zip_source(device, source)

        directory =
          <<0x02014B50::little-32, 20::little-16, 20::little-16, 0x0800::little-16, 0::little-16,
            0::little-16, 0x21::little-16, crc::little-32, size::little-32, size::little-32,
            byte_size(name)::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-16,
            0::little-32, offset::little-32, name::binary>>

        {[directory | directories], offset + byte_size(local) + size}
      end)

    central = directories |> Enum.reverse() |> IO.iodata_to_binary()
    :ok = IO.binwrite(device, central)
    count = length(entries)

    IO.binwrite(
      device,
      <<0x06054B50::little-32, 0::little-16, 0::little-16, count::little-16, count::little-16,
        byte_size(central)::little-32, offset::little-32, 0::little-16>>
    )
  end

  defp zip_source_info({:binary, bytes}), do: {byte_size(bytes), :erlang.crc32(bytes)}

  defp zip_source_info({:file, path}) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce({0, 0}, fn chunk, {size, crc} ->
      {size + byte_size(chunk), :erlang.crc32(crc, chunk)}
    end)
  end

  defp write_zip_source(device, {:binary, bytes}), do: IO.binwrite(device, bytes)

  defp write_zip_source(device, {:file, path}) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.each(fn chunk -> :ok = IO.binwrite(device, chunk) end)

    :ok
  end

  defp list_and_validate(path) do
    case :zip.list_dir(String.to_charlist(path)) do
      {:ok, entries} -> validate_entries(entries)
      {:error, reason} -> {:error, {:invalid_archive, reason}}
    end
  end

  defp validate_entries(entries) do
    files = Enum.reject(entries, &(elem(&1, 0) == :zip_comment))

    with true <- length(files) <= @max_files || {:error, :too_many_files},
         {:ok, validated} <- validate_each_entry(files),
         true <-
           Enum.any?(validated, &(&1.name == @manifest and &1.type == :regular)) ||
             {:error, :missing_manifest},
         true <-
           Enum.any?(validated, &(&1.name == @checksums and &1.type == :regular)) ||
             {:error, :missing_checksums},
         true <-
           Enum.sum(Enum.map(validated, & &1.size)) <= @max_total_size ||
             {:error, :archive_too_large} do
      {:ok, validated}
    end
  end

  defp validate_each_entry(entries) do
    Enum.reduce_while(entries, {:ok, {[], MapSet.new()}}, fn
      {:zip_file, raw_name, info, _, _, _}, {:ok, {valid, seen}} ->
        name = List.to_string(raw_name)
        size = elem(info, 1)
        type = elem(info, 2)
        normalized = String.trim_trailing(name, "/")
        identity = String.downcase(normalized)

        cond do
          not safe_relative_path?(name) ->
            {:halt, {:error, {:unsafe_path, name}}}

          MapSet.member?(seen, identity) ->
            {:halt, {:error, {:duplicate_path, name}}}

          type not in [:regular, :directory] ->
            {:halt, {:error, {:unsupported_file, name}}}

          size > @max_file_size ->
            {:halt, {:error, {:file_too_large, name}}}

          true ->
            item = %{name: normalized, size: size, type: type}
            {:cont, {:ok, {[item | valid], MapSet.put(seen, identity)}}}
        end

      _, _ ->
        {:halt, {:error, :invalid_zip_entry}}
    end)
    |> case do
      {:ok, {valid, _seen}} -> {:ok, valid}
      error -> error
    end
  end

  defp safe_relative_path?(name) do
    segments = String.split(String.trim_trailing(name, "/"), "/")

    not String.contains?(name, ["\\", <<0>>]) and
      name != "" and
      not String.starts_with?(name, "/") and
      not Regex.match?(~r/^[A-Za-z]:/, name) and
      Enum.all?(segments, fn segment ->
        segment not in ["", ".", ".."] and
          not Regex.match?(~r/[<>:"|?*\x00-\x1f]/u, segment) and
          not String.ends_with?(segment, [" ", "."])
      end)
  end

  defp extract(path, content) do
    case :zip.extract(String.to_charlist(path), cwd: String.to_charlist(content)) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, {:invalid_archive, reason}}
    end
  end

  defp validate_extracted(content, entries) do
    with {:ok, manifest_bytes} <- File.read(Path.join(content, @manifest)),
         {:ok, checksums_bytes} <- File.read(Path.join(content, @checksums)),
         {:ok, manifest} <- Jason.decode(manifest_bytes),
         :ok <- validate_manifest(manifest),
         {:ok, declared} <- parse_checksums(checksums_bytes),
         :ok <- validate_checksums(content, entries, declared) do
      {:ok, manifest}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_manifest}
      {:error, :enoent} -> {:error, :invalid_archive}
      error -> error
    end
  end

  defp validate_manifest(%{
         "formatVersion" => @format_version,
         "instance" => %{
           "id" => id,
           "experienceId" => experience_id,
           "experienceVersion" => experience_version,
           "name" => name,
           "slug" => slug,
           "config" => config,
           "participantCodeDigest" => digest,
           "participantCodeVersion" => version
         }
       })
       when is_binary(experience_id) and byte_size(experience_id) > 0 and
              is_binary(experience_version) and byte_size(experience_version) > 0 and
              is_binary(name) and
              byte_size(name) >= 2 and byte_size(name) <= 80 and is_map(config) and
              (is_nil(slug) or is_binary(slug)) and (is_nil(digest) or is_binary(digest)) and
              is_integer(version) and version >= 0 do
    with {:ok, canonical} when canonical == id <- Ecto.UUID.cast(id),
         true <- valid_slug?(slug),
         true <- valid_digest?(digest) do
      :ok
    else
      _ -> {:error, :invalid_manifest}
    end
  end

  defp validate_manifest(_), do: {:error, :invalid_manifest}

  defp valid_slug?(nil), do: true

  defp valid_slug?(slug),
    do: byte_size(slug) in 2..60 and Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug)

  defp valid_digest?(nil), do: true

  defp valid_digest?(digest) do
    case String.split(digest, ".", parts: 2) do
      [salt, hash] ->
        match?({:ok, bytes} when byte_size(bytes) == 16, Base.url_decode64(salt, padding: false)) and
          match?(
            {:ok, bytes} when byte_size(bytes) == 32,
            Base.url_decode64(hash, padding: false)
          )

      _ ->
        false
    end
  end

  defp parse_checksums(bytes) do
    bytes
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn line, {:ok, acc} ->
      case String.split(line, "  ", parts: 2) do
        [digest, name]
        when byte_size(digest) == 64 and not is_map_key(acc, name) ->
          if Regex.match?(~r/^[0-9a-f]{64}$/, digest) and safe_relative_path?(name) do
            {:cont, {:ok, Map.put(acc, name, digest)}}
          else
            {:halt, {:error, :invalid_checksums}}
          end

        _ ->
          {:halt, {:error, :invalid_checksums}}
      end
    end)
  end

  defp validate_checksums(content, entries, declared) do
    expected =
      entries
      |> Enum.filter(&(&1.type == :regular and &1.name != @checksums))
      |> Enum.map(& &1.name)
      |> MapSet.new()

    if MapSet.new(Map.keys(declared)) != expected do
      {:error, :checksum_mismatch}
    else
      Enum.reduce_while(declared, :ok, fn {name, digest}, :ok ->
        actual = sha256_file!(Path.join(content, name))

        if Plug.Crypto.secure_compare(actual, digest),
          do: {:cont, :ok},
          else: {:halt, {:error, :checksum_mismatch}}
      end)
    end
  rescue
    _ -> {:error, :checksum_mismatch}
  end

  defp remove_control_files(content) do
    with :ok <- File.rm(Path.join(content, @manifest)),
         :ok <- File.rm(Path.join(content, @checksums)) do
      :ok
    end
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp sha256_file!(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp safe_filename(name) do
    case name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-") |> String.trim("-") do
      "" -> "wakecanvas-instance"
      value -> value
    end
  end

  defp data_root, do: Application.fetch_env!(:wake_canvas, :data_root)
end
