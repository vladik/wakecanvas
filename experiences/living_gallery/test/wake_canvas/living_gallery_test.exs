defmodule WakeCanvas.Experience.LivingGalleryTest do
  use ExUnit.Case

  alias WakeCanvas.Experience.LivingGallery.Config

  test "declares stable Experience identity" do
    definition = WakeCanvas.Experience.LivingGallery.definition()

    assert definition.id == "org.wakecanvas.experience.living-gallery"
    assert definition.otp_application == :wake_canvas_experience_living_gallery
    assert :camera in definition.capabilities
    assert Enum.find(definition.surfaces, &(&1.id == :moments)).path == "moments"
    assert definition.default_display_variant == "living-collage"

    assert Enum.map(definition.display_variants, & &1.id) == [
             "living-collage",
             "quiet-spotlight"
           ]
  end

  test "uses separate safe auto-publish defaults for each content type" do
    assert Config.auto_publish?(%{}, "artwork")
    refute Config.auto_publish?(%{}, "workshop_moment")

    assert Config.auto_publish?(%{"moments_auto_publish" => true}, "workshop_moment")
    refute Config.auto_publish?(%{"artwork_auto_publish" => false}, "artwork")
    assert Config.with_defaults(%{})["display_variant"] == "living-collage"
  end
end
