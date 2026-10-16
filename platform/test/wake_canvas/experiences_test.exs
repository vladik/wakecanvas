defmodule WakeCanvas.ExperiencesTest do
  use WakeCanvas.DataCase

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Package
  alias WakeCanvas.Repo

  setup do
    package =
      Repo.insert!(%Package{
        id: "org.wakecanvas.test",
        name: "Test Experience",
        version: "1.0.0"
      })

    %{package: package}
  end

  test "creates integer-ID instances and activates only one", %{package: package} do
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

    assert is_integer(morning.id)
    assert {:ok, _morning} = Experiences.activate_instance(morning.id)
    assert Experiences.active_instance().id == morning.id

    assert {:ok, _evening} = Experiences.activate_instance(evening.id)
    assert Experiences.active_instance().id == evening.id
    refute Experiences.get_instance!(morning.id).active
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
end
