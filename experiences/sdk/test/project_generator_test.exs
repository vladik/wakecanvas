defmodule WakeCanvas.ExperienceSDK.ProjectGeneratorTest do
  use ExUnit.Case, async: true

  alias WakeCanvas.ExperienceSDK.ProjectGenerator

  test "generates a standalone package-ready Experience" do
    root = Path.join(System.tmp_dir!(), "wakecanvas-new-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, generated_root} =
             ProjectGenerator.generate(root,
               app: "sound_garden",
               module: "ArtistStudio.SoundGarden",
               id: "com.artiststudio.experience.sound-garden",
               name: "Sound Garden",
               sdk_path: File.cwd!()
             )

    assert generated_root == Path.expand(root)

    assert File.read!(Path.join(root, "mix.exs")) =~ "app: :sound_garden"

    assert File.read!(Path.join(root, "wakecanvas-experience.json")) =~
             "com.artiststudio.experience.sound-garden"

    assert File.read!(Path.join(root, "priv/static/variants/default.js")) =~
             "export function mount"

    display = File.read!(Path.join(root, "lib/artist_studio/sound_garden/display_live.ex"))
    assert display =~ "renderer:diagnostic"
    assert display =~ "renderer_diagnostics_api"
  end

  test "refuses to overwrite a non-empty destination" do
    root =
      Path.join(System.tmp_dir!(), "wakecanvas-existing-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "keep.txt"), "keep")
    on_exit(fn -> File.rm_rf!(root) end)

    assert {:error, :destination_not_empty} =
             ProjectGenerator.generate(root,
               app: "demo",
               module: "Demo",
               id: "org.example.demo",
               name: "Demo",
               sdk_path: File.cwd!()
             )

    assert File.read!(Path.join(root, "keep.txt")) == "keep"
  end
end
