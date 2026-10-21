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

  test "exports a normal instance without changing its lifecycle", %{package: package} do
    {:ok, instance} =
      Experiences.create_instance(%{
        name: "Live Workshop",
        experience_id: package.id,
        config: %{"display_variant" => "default"}
      })

    write_instance_file!(instance.id, "experience.sqlite", "snapshot database")
    write_instance_file!(instance.id, "media/artwork.png", "snapshot image")

    assert {:ok, archive} = Experiences.export_instance(instance.id)
    assert File.exists?(archive.path)

    unchanged = Experiences.get_instance!(instance.id)
    refute unchanged.active
    assert is_nil(unchanged.archived_at)
    assert File.read!(InstancePaths.database_path(instance.id)) == "snapshot database"

    assert File.read!(Path.join(InstancePaths.media_dir(instance.id), "artwork.png")) ==
             "snapshot image"
  end

  test "exports a consistent SQLite snapshot without archiving", %{package: package} do
    {:ok, instance} =
      Experiences.create_instance(%{
        name: "SQLite Workshop",
        experience_id: package.id
      })

    InstancePaths.ensure!(instance.id)
    database = InstancePaths.database_path(instance.id)
    {:ok, connection} = Exqlite.Sqlite3.open(database)
    :ok = Exqlite.Sqlite3.execute(connection, "PRAGMA journal_mode=WAL")
    :ok = Exqlite.Sqlite3.execute(connection, "CREATE TABLE contributions (body TEXT)")
    :ok = Exqlite.Sqlite3.execute(connection, "INSERT INTO contributions VALUES ('hello')")
    :ok = Exqlite.Sqlite3.close(connection)

    assert {:ok, archive} = Experiences.export_instance(instance.id)
    assert {:ok, copy} = Experiences.import_instance(archive.path, :clone)

    {:ok, snapshot} =
      Exqlite.Sqlite3.open(InstancePaths.database_path(copy.id), mode: :readonly)

    {:ok, statement} =
      Exqlite.Sqlite3.prepare(snapshot, "SELECT body FROM contributions")

    assert {:row, ["hello"]} = Exqlite.Sqlite3.step(snapshot, statement)
    :ok = Exqlite.Sqlite3.release(snapshot, statement)
    :ok = Exqlite.Sqlite3.close(snapshot)
    assert is_nil(Experiences.get_instance!(instance.id).archived_at)
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

  test "a normal management import is immediately available but remains stopped", %{
    package: package
  } do
    instance = archived_instance!(package, "Ready Workshop", "ready-workshop")
    write_instance_file!(instance.id, "experience.sqlite", "ready")
    assert {:ok, archive} = Experiences.export_instance(instance.id)
    assert {:ok, _} = Experiences.purge_instance(instance.id, instance.name)

    assert {:ok, imported} =
             Experiences.import_instance(archive.path, :preserve, "", :available)

    refute imported.active
    assert is_nil(imported.archived_at)
    assert Experiences.get_instance!(imported.id).id == imported.id
    refute Enum.any?(Experiences.list_archived_instances(), &(&1.id == imported.id))
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
