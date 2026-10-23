defmodule WakeCanvas.Experience.LivingGalleryTest do
  use ExUnit.Case

  alias WakeCanvas.Experience.LivingGallery.Config

  test "migrates an assigned instance database through the SDK lifecycle" do
    root =
      Path.join(
        System.tmp_dir!(),
        "wakecanvas-lg-migration-#{System.unique_integer([:positive])}"
      )

    database = Path.join(root, "experience.sqlite")

    instance = %WakeCanvas.ExperienceSDK.Instance{
      id: Ecto.UUID.generate(),
      experience_id: "org.wakecanvas.experience.living-gallery",
      experience_version: "0.2.0",
      name: "Migration test",
      config: %{},
      data_dir: root,
      database_path: database
    }

    on_exit(fn -> File.rm_rf(root) end)

    assert :ok = WakeCanvas.Experience.LivingGallery.migrate_instance(instance)
    assert File.regular?(database)
    assert [] = WakeCanvas.Experience.LivingGallery.Store.list(database)
  end

  test "declares stable Experience identity" do
    definition = WakeCanvas.Experience.LivingGallery.definition()

    assert definition.id == "org.wakecanvas.experience.living-gallery"
    assert definition.otp_application == :wake_canvas_experience_living_gallery
    assert :camera in definition.capabilities
    assert :microphone in definition.capabilities
    assert Enum.find(definition.surfaces, &(&1.id == :moments)).path == "moments"
    assert Enum.find(definition.surfaces, &(&1.id == :messages)).path == "messages"
    assert definition.default_display_variant == "living-collage"
    assert definition.config_schema["retain_originals"].default
    assert definition.config_schema["presentation_label"].default == "Living Gallery"
    assert definition.config_schema["presentation_title"].default == ""

    assert Enum.find(definition.display_variants, &(&1.id == "living-collage")).label ==
             "Living Film Collage"

    assert Enum.find(definition.display_variants, &(&1.id == "gallery-orbit")).label ==
             "Living Spiral"

    assert Enum.find(definition.display_variants, &(&1.id == "gallery-orbit-focus")).label ==
             "Living Spiral — Focus"

    assert Enum.map(definition.display_variants, & &1.id) == [
             "living-collage",
             "quiet-spotlight",
             "gallery-orbit",
             "gallery-orbit-focus",
             "growing-canvas",
             "community-tapestry",
             "gravity-playground"
           ]
  end

  test "uses separate safe auto-publish defaults for each content type" do
    assert Config.auto_publish?(%{}, "artwork")
    refute Config.auto_publish?(%{}, "workshop_moment")
    refute Config.auto_publish?(%{}, "message")

    assert Config.auto_publish?(%{"moments_auto_publish" => true}, "workshop_moment")
    assert Config.auto_publish?(%{"messages_auto_publish" => true}, "message")
    refute Config.auto_publish?(%{"artwork_auto_publish" => false}, "artwork")
    assert Config.retain_originals?(%{})
    refute Config.retain_originals?(%{"retain_originals" => false})
    assert Config.with_defaults(%{})["display_variant"] == "living-collage"
    assert Config.with_defaults(%{})["presentation_label"] == "Living Gallery"
    assert Config.with_defaults(%{})["presentation_title"] == ""
    assert Config.with_defaults(%{})["presentation_description"] == ""
  end
end
