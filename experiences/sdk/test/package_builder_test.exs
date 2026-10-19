defmodule WakeCanvas.ExperienceSDK.PackageBuilderTest do
  use ExUnit.Case, async: true

  alias WakeCanvas.ExperienceSDK.PackageBuilder

  test "builds byte-for-byte deterministic archives with complete checksums" do
    root = tmp_dir()
    app_path = Path.join(root, "app")
    File.mkdir_p!(Path.join(app_path, "ebin"))
    File.mkdir_p!(Path.join(app_path, "priv/static"))
    File.write!(Path.join(app_path, "ebin/Elixir.Demo.beam"), "beam")
    File.write!(Path.join(app_path, "priv/static/app.js"), "export default 1")

    manifest = Path.join(root, "wakecanvas-experience.json")

    File.write!(
      manifest,
      Jason.encode!(%{
        "manifestVersion" => 1,
        "experienceId" => "org.example.demo",
        "version" => "1.2.3",
        "otpApplication" => "demo",
        "entryModule" => "Demo"
      })
    )

    first = Path.join(root, "first.wakecanvas")
    second = Path.join(root, "second.wakecanvas")
    assert {:ok, one} = PackageBuilder.build(manifest, app_path, first)
    assert {:ok, two} = PackageBuilder.build(manifest, app_path, second)
    assert one.digest == two.digest
    assert File.read!(first) == File.read!(second)

    assert {:ok, entries} = :zip.extract(String.to_charlist(first), [:memory])
    entries = Map.new(entries, fn {name, bytes} -> {List.to_string(name), bytes} end)
    assert entries["lib/demo-1.2.3/ebin/Elixir.Demo.beam"] == "beam"
    assert entries["CHECKSUMS"] =~ "wakecanvas-experience.json"
    assert entries["CHECKSUMS"] =~ "lib/demo-1.2.3/priv/static/app.js"
  end

  defp tmp_dir do
    path = Path.join(System.tmp_dir!(), "wakecanvas-sdk-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
