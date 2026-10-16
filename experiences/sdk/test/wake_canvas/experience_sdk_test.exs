defmodule WakeCanvas.ExperienceSDKTest do
  use ExUnit.Case
  doctest WakeCanvas.ExperienceSDK

  test "exposes a semantic SDK version" do
    assert {:ok, _version} = Version.parse(WakeCanvas.ExperienceSDK.version())
  end

  test "represents isolated Experience instance context" do
    instance = %WakeCanvas.ExperienceSDK.Instance{
      id: 12,
      experience_id: "org.wakecanvas.experience.living-gallery",
      experience_version: "0.1.0",
      name: "Morning Workshop",
      config: %{"moderationRequired" => true},
      data_dir: "data/instances/12",
      database_path: "data/instances/12/experience.sqlite"
    }

    assert instance.name == "Morning Workshop"
    assert instance.id == 12
    assert instance.experience_id == "org.wakecanvas.experience.living-gallery"
  end

  test "represents a stable declared display variant" do
    variant = %WakeCanvas.ExperienceSDK.DisplayVariant{
      id: "quiet-spotlight",
      label: "Quiet Spotlight",
      description: "A calm single-artwork presentation"
    }

    assert variant.id == "quiet-spotlight"
  end
end
