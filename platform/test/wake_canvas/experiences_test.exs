defmodule WakeCanvas.ExperiencesTest do
  use WakeCanvas.DataCase

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Package
  alias WakeCanvas.ExperienceSDK.{Definition, PackageBuilder}
  alias WakeCanvas.Repo

  setup do
    package =
      Repo.get(Package, "org.wakecanvas.test-display") ||
        Repo.insert!(%Package{
          id: "org.wakecanvas.test-display",
          name: "Test Experience",
          version: "1.0.0"
        })

    %{package: package}
  end

  test "registers a source-linked development Experience in the catalog" do
    definition = %Definition{
      id: "org.example.experience.source-linked",
      name: "Source Linked",
      version: "0.3.0",
      otp_application: :source_linked,
      surfaces: []
    }

    assert {:ok, package} = Experiences.register_development_package(definition)
    assert package.id == definition.id
    assert package.name == "Source Linked"
    assert package.version == "0.3.0"
    assert package.status == "installed"
    assert is_nil(package.archive_digest)
  end

  test "creates UUID instances and activates only one", %{package: package} do
    assert {:ok, morning} =
             Experiences.create_instance(%{
               name: "Morning Workshop",
               experience_id: package.id
             })

    assert {:ok, evening} =
             Experiences.create_instance(%{
               name: "Evening Workshop",
               experience_id: package.id
             })

    assert {:ok, parsed_id} = Ecto.UUID.cast(morning.id)
    assert parsed_id == morning.id
    assert {:ok, _morning} = Experiences.activate_instance(morning.id)
    assert Experiences.active_instance().id == morning.id

    assert File.read!(Path.join(Experiences.InstancePaths.data_dir(morning.id), "migration-ran")) ==
             "1.0.0"

    assert {:ok, _evening} = Experiences.activate_instance(evening.id)
    assert Experiences.active_instance().id == evening.id

    assert File.exists?(
             Path.join(Experiences.InstancePaths.data_dir(evening.id), "migration-ran")
           )

    refute Experiences.get_instance!(morning.id).active
  end

  test "stages a validated external package and records restart-required state" do
    root = package_fixture_root("install")

    archive =
      build_package(root, "org.example.external-demo", "external_demo", "ExternalDemo", "1.0.0")

    digest =
      archive |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    assert {:ok, installed} = Experiences.stage_package_install(archive)
    assert installed.id == "org.example.external-demo"
    assert installed.status == "pending_restart"
    assert installed.archive_digest == digest
    assert installed.manifest["entryModule"] == "ExternalDemo"
  end

  test "retains one rollback point and swaps package versions safely" do
    root = package_fixture_root("rollback")

    first_archive =
      build_package(root, "org.example.rollback", "rollback_demo", "RollbackDemo", "1.0.0")

    second_archive =
      build_package(root, "org.example.rollback", "rollback_demo", "RollbackDemo", "2.0.0")

    assert {:ok, first} = Experiences.stage_package_install(first_archive)
    first = first |> Ecto.Changeset.change(status: "installed") |> Repo.update!()
    assert {:ok, second} = Experiences.stage_package_install(second_archive)
    assert second.version == "2.0.0"
    assert second.previous_archive_digest == first.archive_digest
    assert second.previous_manifest["version"] == "1.0.0"

    assert {:ok, rolled_back} = Experiences.rollback_package(second.id)
    assert rolled_back.status == "pending_restart"
    assert rolled_back.version == "1.0.0"
    assert rolled_back.archive_digest == first.archive_digest
    assert rolled_back.previous_archive_digest == second.archive_digest
  end

  test "uninstall requires exact confirmation, blocks referenced packages, and removes caches" do
    root = package_fixture_root("uninstall")

    archive =
      build_package(root, "org.example.uninstall", "uninstall_demo", "UninstallDemo", "1.0.0")

    assert {:ok, package} = Experiences.stage_package_install(archive)
    cache_path = WakeCanvas.Experiences.PackageArchive.cache_path(package.archive_digest)
    assert File.dir?(cache_path)

    assert {:error, :confirmation_mismatch} =
             Experiences.uninstall_package(package.id, "wrong")

    {:ok, instance} =
      Experiences.create_instance(%{name: "Referenced", experience_id: package.id})

    assert {:ok, _} = Experiences.archive_instance(instance.id)

    assert {:error, {:instances_exist, 1}} =
             Experiences.uninstall_package(package.id, package.name)

    assert {:ok, _} = Experiences.purge_instance(instance.id, instance.name)
    assert {:ok, _} = Experiences.uninstall_package(package.id, package.name)
    refute Repo.get(Package, package.id)
    refute File.exists?(cache_path)
  end

  test "resolves an optional URL slug without replacing UUID identity", %{package: package} do
    assert {:ok, instance} =
             Experiences.create_instance(%{
               name: "Saturday Workshop",
               slug: "Saturday-Workshop",
               experience_id: package.id
             })

    assert instance.slug == "saturday-workshop"
    assert Experiences.get_instance(instance.id).id == instance.id
    assert Experiences.get_instance(instance.slug).id == instance.id
  end

  test "merges Experience configuration without replacing unrelated settings", %{package: package} do
    {:ok, instance} =
      Experiences.create_instance(%{
        name: "Configurable Workshop",
        experience_id: package.id,
        config: %{"visual_theme" => "paper"}
      })

    assert {:ok, updated} =
             Experiences.update_instance_config(instance, %{"artwork_auto_publish" => true})

    assert updated.config == %{
             "visual_theme" => "paper",
             "artwork_auto_publish" => true
           }
  end

  test "does not archive the active instance", %{package: package} do
    {:ok, instance} =
      Experiences.create_instance(%{name: "Workshop", experience_id: package.id})

    {:ok, _instance} = Experiences.activate_instance(instance.id)

    assert {:error, :active_instance} = Experiences.archive_instance(instance.id)
  end

  test "archived instances can be restored without changing their ID", %{package: package} do
    {:ok, archived} =
      Experiences.create_instance(%{name: "Temporary Workshop", experience_id: package.id})

    assert {:ok, _instance} = Experiences.archive_instance(archived.id)
    assert Experiences.get_instance(archived.id) == nil
    assert Enum.any?(Experiences.list_archived_instances(), &(&1.id == archived.id))

    assert {:ok, restored} = Experiences.restore_instance(archived.id)
    assert restored.id == archived.id
    assert Experiences.get_instance(archived.id).id == archived.id
  end

  test "archiving an instance preserves its complete data directory", %{package: package} do
    {:ok, instance} =
      Experiences.create_instance(%{name: "Disposable Workshop", experience_id: package.id})

    data_dir = WakeCanvas.Experiences.InstancePaths.data_dir(instance.id)
    File.mkdir_p!(Path.join(data_dir, "media"))
    File.write!(Path.join(data_dir, "experience.sqlite"), "database")
    File.write!(Path.join(data_dir, "media/photo.jpg"), "image")

    assert {:ok, _instance} = Experiences.archive_instance(instance.id)
    assert File.exists?(data_dir)
    assert File.exists?(Path.join(data_dir, "experience.sqlite"))
    assert File.exists?(Path.join(data_dir, "media/photo.jpg"))
  end

  test "only an archived instance with exact confirmation can be permanently purged", %{
    package: package
  } do
    {:ok, instance} =
      Experiences.create_instance(%{name: "Purge This Workshop", experience_id: package.id})

    data_dir = WakeCanvas.Experiences.InstancePaths.data_dir(instance.id)
    File.mkdir_p!(Path.join(data_dir, "media"))
    File.write!(Path.join(data_dir, "media/photo.jpg"), "image")

    assert {:error, :not_archived} = Experiences.purge_instance(instance.id, instance.name)
    assert {:ok, _} = Experiences.archive_instance(instance.id)
    assert {:error, :confirmation_mismatch} = Experiences.purge_instance(instance.id, "wrong")
    assert File.exists?(data_dir)

    assert {:ok, _} = Experiences.purge_instance(instance.id, instance.name)
    refute Repo.get(WakeCanvas.Experiences.Instance, instance.id)
    refute File.exists?(data_dir)
  end

  defp package_fixture_root(label) do
    root =
      Path.join(System.tmp_dir!(), "wakecanvas-#{label}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp build_package(root, id, app, entry_module, version) do
    app_path = Path.join(root, "app-#{version}")
    File.mkdir_p!(Path.join(app_path, "ebin"))
    File.mkdir_p!(Path.join(app_path, "priv/static/variants"))
    module = Module.concat([entry_module])

    File.write!(
      Path.join(app_path, "ebin/#{app}.app"),
      app_spec(String.to_atom(app), version, [module])
    )

    File.write!(Path.join(app_path, "ebin/Elixir.#{entry_module}.beam"), beam(module))
    File.write!(Path.join(app_path, "priv/static/experience.css"), ".experience {}")

    File.write!(
      Path.join(app_path, "priv/static/variants/default.js"),
      "export function mount() {}"
    )

    manifest_path = Path.join(root, "manifest-#{version}.json")

    File.write!(
      manifest_path,
      Jason.encode!(%{
        "manifestVersion" => 1,
        "experienceId" => id,
        "name" => entry_module,
        "version" => version,
        "otpApplication" => app,
        "entryModule" => entry_module,
        "sdkRequirement" => ">= 0.1.0 and < 1.0.0",
        "platformRequirement" => ">= 0.1.0 and < 1.0.0",
        "elixirRequirement" => ">= 1.20.0 and < 2.0.0",
        "otpRequirement" => ">= 29.0.0 and < 30.0.0",
        "target" => "any",
        "surfaces" => [
          %{"id" => "display", "path" => "display", "module" => entry_module, "role" => "display"}
        ],
        "defaultDisplayVariant" => "default",
        "displayVariants" => [
          %{
            "id" => "default",
            "label" => "Default",
            "entrypoint" => "static/variants/default.js"
          }
        ],
        "browser" => %{"stylesheet" => "static/experience.css"}
      })
    )

    archive = Path.join(root, "#{app}-#{version}.wakecanvas")
    {:ok, _} = PackageBuilder.build(manifest_path, app_path, archive)
    archive
  end

  defp beam(module) do
    {:ok, ^module, bytes, _warnings} =
      :compile.forms(
        [{:attribute, 1, :module, module}, {:attribute, 1, :export, []}],
        [:return_errors, :return_warnings]
      )

    bytes
  end

  defp app_spec(application, version, modules) do
    term =
      {:application, application,
       [
         description: ~c"test",
         vsn: String.to_charlist(version),
         modules: modules,
         registered: [],
         applications: [:kernel, :stdlib]
       ]}

    :io_lib.format(~c"~p.~n", [term]) |> IO.iodata_to_binary()
  end
end
