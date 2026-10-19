defmodule WakeCanvas.Experiences.InstanceArchiveTest do
  use WakeCanvas.DataCase, async: false

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.{InstanceArchive, InstancePaths, Package}
  alias WakeCanvas.Repo

  setup do
    root =
      Path.join(System.tmp_dir!(), "wakecanvas-instance-#{System.unique_integer([:positive])}")

    original_root = Application.fetch_env!(:wake_canvas, :data_root)
    Application.put_env(:wake_canvas, :data_root, root)

    package =
      Repo.insert!(%Package{
        id: "org.example.portable-#{System.unique_integer([:positive])}",
        name: "Portable Experience",
        version: "1.0.0",
        status: "installed"
      })

    on_exit(fn ->
      Application.put_env(:wake_canvas, :data_root, original_root)
      File.rm_rf!(root)
    end)

    %{root: root, package: package}
  end

  test "exports an archived instance and imports it with the stable UUID", %{package: package} do
    instance = archived_instance!(package, "Portable Workshop", "portable-workshop")
    write_instance_file!(instance.id, "experience.sqlite", "opaque sqlite bytes")
    write_instance_file!(instance.id, "media/artwork.png", "image bytes")

    assert {:ok, archive} = Experiences.export_instance(instance.id)
    assert File.exists?(archive.path)

    assert {:ok, _} = Experiences.purge_instance(instance.id, instance.name)
    refute Repo.get(WakeCanvas.Experiences.Instance, instance.id)

    assert {:ok, imported} = Experiences.import_instance(archive.path)
    assert imported.id == instance.id
    assert imported.name == instance.name
    assert imported.slug == instance.slug
    refute imported.active
    assert imported.archived_at
    assert File.read!(InstancePaths.database_path(imported.id)) == "opaque sqlite bytes"

    assert File.read!(Path.join(InstancePaths.media_dir(imported.id), "artwork.png")) ==
             "image bytes"
  end

  test "a collision can create an independent copy", %{package: package} do
    instance = archived_instance!(package, "Morning Workshop", "morning-workshop")
    write_instance_file!(instance.id, "experience.sqlite", "source")
    assert {:ok, archive} = Experiences.export_instance(instance.id)

    assert {:error, :instance_exists} = Experiences.import_instance(archive.path)
    assert {:ok, copy} = Experiences.import_instance(archive.path, :clone)

    assert copy.id != instance.id
    assert copy.name == "Morning Workshop (Copy)"
    assert is_nil(copy.slug)
    assert copy.archived_at
    assert File.read!(InstancePaths.database_path(copy.id)) == "source"
  end

  test "replacement requires an archived instance and exact name", %{package: package} do
    instance = archived_instance!(package, "Replace Me", "replace-me")
    write_instance_file!(instance.id, "experience.sqlite", "exported")
    assert {:ok, archive} = Experiences.export_instance(instance.id)
    write_instance_file!(instance.id, "experience.sqlite", "local changes")

    assert {:error, :confirmation_mismatch} =
             Experiences.import_instance(archive.path, :replace, "wrong")

    assert {:ok, replaced} = Experiences.import_instance(archive.path, :replace, "Replace Me")
    assert replaced.id == instance.id
    assert replaced.archived_at
    assert File.read!(InstancePaths.database_path(instance.id)) == "exported"
  end

  test "rejects path traversal before extraction", %{root: root} do
    archive = Path.join(root, "unsafe.wakecanvas-instance")

    {:ok, _} =
      :zip.create(String.to_charlist(archive), [
        {~c"wakecanvas-instance.json", "{}"},
        {~c"CHECKSUMS", ""},
        {~c"../outside.txt", "unsafe"}
      ])

    assert {:error, {:unsafe_path, "../outside.txt"}} = InstanceArchive.stage(archive)
    refute File.exists?(Path.join(root, "outside.txt"))
  end

  test "rejects a payload changed after checksums were written", %{package: package, root: root} do
    instance = archived_instance!(package, "Checksum Workshop", nil)
    write_instance_file!(instance.id, "experience.sqlite", "original")
    assert {:ok, archive} = Experiences.export_instance(instance.id)
    {:ok, entries} = :zip.extract(String.to_charlist(archive.path), [:memory])

    entries =
      Enum.map(entries, fn
        {~c"experience.sqlite", _bytes} -> {~c"experience.sqlite", "tampered"}
        entry -> entry
      end)

    tampered = Path.join(root, "tampered.wakecanvas-instance")
    {:ok, _} = :zip.create(String.to_charlist(tampered), entries)
    assert {:error, :checksum_mismatch} = Experiences.import_instance(tampered)
  end

  defp archived_instance!(package, name, slug) do
    {:ok, instance} =
      Experiences.create_instance(%{
        name: name,
        slug: slug,
        experience_id: package.id,
        config: %{"display_variant" => "default"}
      })

    {:ok, archived} = Experiences.archive_instance(instance.id)
    archived
  end

  defp write_instance_file!(id, relative, contents) do
    path = Path.join(InstancePaths.data_dir(id), relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end
end
