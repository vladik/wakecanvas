defmodule WakeCanvas.Experiences.BundledInstanceInstallerTest do
  use WakeCanvas.DataCase, async: false

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.{BundledInstanceInstaller, InstancePaths, Package}
  alias WakeCanvas.Repo

  setup do
    root = Path.join(System.tmp_dir!(), "wakecanvas-seed-#{System.unique_integer([:positive])}")
    original_root = Application.fetch_env!(:wake_canvas, :data_root)
    Application.put_env(:wake_canvas, :data_root, root)

    if active = Experiences.active_instance() do
      {:ok, _} = Experiences.stop_instance(active.id)
    end

    base_instance_count = Repo.aggregate(WakeCanvas.Experiences.Instance, :count)

    package =
      Repo.get(Package, "org.wakecanvas.test-display") ||
        Repo.insert!(%Package{
          id: "org.wakecanvas.test-display",
          name: "Test Display",
          version: "1.0.0",
          status: "installed"
        })

    on_exit(fn ->
      Application.put_env(:wake_canvas, :data_root, original_root)
      File.rm_rf!(root)
    end)

    %{root: root, package: package, base_instance_count: base_instance_count}
  end

  test "imports a bundled instance once without replacing later operator changes", %{
    root: root,
    package: package,
    base_instance_count: base_instance_count
  } do
    archive = exported_seed!(package, "Artist Demo")
    seed_directory = Path.dirname(archive)

    windows_directory = String.replace(seed_directory, "/", "\\")
    first = BundledInstanceInstaller.install_from(windows_directory)
    [{_archive, {:imported, imported}}] = first.archives
    assert imported.archived_at

    imported
    |> Ecto.Changeset.change(name: "Artist Renamed Demo")
    |> Repo.update!()

    File.write!(Path.join(InstancePaths.data_dir(imported.id), "operator-change"), "keep")

    second = BundledInstanceInstaller.install_from(seed_directory)
    [{_archive, {:skipped, skipped}}] = second.archives
    assert skipped.name == "Artist Renamed Demo"
    assert File.read!(Path.join(InstancePaths.data_dir(imported.id), "operator-change")) == "keep"
    assert Repo.aggregate(WakeCanvas.Experiences.Instance, :count) == base_instance_count + 1
    assert File.dir?(root)
  end

  test "restores and activates the first seed only when no instance is active", %{
    package: package,
    base_instance_count: base_instance_count
  } do
    archive = exported_seed!(package, "Ready Demo")

    result = BundledInstanceInstaller.install_from(Path.dirname(archive), true)
    assert {:activated, activated} = result.activation
    assert activated.active
    assert is_nil(activated.archived_at)
    assert Experiences.active_instance().id == activated.id
    assert File.read!(Path.join(InstancePaths.data_dir(activated.id), "migration-ran")) == "1.0.0"

    repeated = BundledInstanceInstaller.install_from(Path.dirname(archive), true)
    assert repeated.activation == :active_instance_preserved
    assert Repo.aggregate(WakeCanvas.Experiences.Instance, :count) == base_instance_count + 1

    assert {:ok, _} = Experiences.stop_instance(activated.id)

    stopped = BundledInstanceInstaller.install_from(Path.dirname(archive), true)
    assert stopped.activation == :seed_already_imported
    refute Experiences.active_instance()
  end

  test "an absent seed directory is a safe no-op" do
    missing =
      Path.join(System.tmp_dir!(), "wakecanvas-missing-#{System.unique_integer([:positive])}")

    assert BundledInstanceInstaller.install_from(nil) == %{archives: [], activation: :disabled}
    assert BundledInstanceInstaller.install_from(missing).archives == []
  end

  defp exported_seed!(package, name) do
    {:ok, instance} =
      Experiences.create_instance(%{
        name: name,
        experience_id: package.id,
        config: %{"display_variant" => "default"}
      })

    File.mkdir_p!(InstancePaths.data_dir(instance.id))
    File.write!(Path.join(InstancePaths.data_dir(instance.id), "seed-content"), "prepared")
    {:ok, archived} = Experiences.archive_instance(instance.id)
    {:ok, export} = Experiences.export_instance(archived.id)
    {:ok, _} = Experiences.purge_instance(archived.id, archived.name)
    export.path
  end
end
