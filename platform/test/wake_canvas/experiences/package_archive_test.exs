defmodule WakeCanvas.Experiences.PackageArchiveTest do
  use ExUnit.Case, async: false

  alias WakeCanvas.ExperienceSDK.PackageBuilder
  alias WakeCanvas.Experiences.PackageArchive

  setup do
    root =
      Path.join(System.tmp_dir!(), "wakecanvas-package-#{System.unique_integer([:positive])}")

    app_path = Path.join(root, "app")
    File.mkdir_p!(Path.join(app_path, "ebin"))
    File.mkdir_p!(Path.join(app_path, "priv/static/variants"))
    File.write!(Path.join(app_path, "ebin/demo.app"), app_spec(:demo, "1.2.3", [Demo]))
    File.write!(Path.join(app_path, "ebin/Elixir.Demo.beam"), beam(Demo))
    File.write!(Path.join(app_path, "priv/static/experience.css"), ".demo {}")

    File.write!(
      Path.join(app_path, "priv/static/variants/default.js"),
      "export function mount() {}"
    )

    manifest_path = Path.join(root, "wakecanvas-experience.json")
    File.write!(manifest_path, Jason.encode!(manifest()))
    archive = Path.join(root, "demo.wakecanvas")
    {:ok, _} = PackageBuilder.build(manifest_path, app_path, archive)

    original_root = Application.fetch_env!(:wake_canvas, :data_root)
    Application.put_env(:wake_canvas, :data_root, Path.join(root, "data"))

    on_exit(fn ->
      Application.put_env(:wake_canvas, :data_root, original_root)
      File.rm_rf!(root)
    end)

    %{archive: archive, root: root, app_path: app_path, manifest_path: manifest_path}
  end

  test "validates checksums and stages to a content-addressed cache", %{archive: archive} do
    assert {:ok, package} = PackageArchive.stage(archive)
    assert package.manifest["experienceId"] == "org.example.demo"
    assert String.ends_with?(package.cache_path, "sha256-#{package.digest}")

    assert File.read!(
             Path.join(package.cache_path, "lib/demo-1.2.3/priv/static/variants/default.js")
           ) == "export function mount() {}"

    assert {:ok, same} = PackageArchive.stage(archive)
    assert same.cache_path == package.cache_path

    File.write!(
      Path.join(package.cache_path, "lib/demo-1.2.3/priv/static/variants/default.js"),
      "changed"
    )

    assert {:error, {:cache_invalid, :checksum_mismatch}} = PackageArchive.stage(archive)
  end

  test "rejects a checksum-invalid archive", %{archive: archive, root: root} do
    {:ok, entries} = :zip.extract(String.to_charlist(archive), [:memory])

    entries =
      Enum.map(entries, fn
        {~c"lib/demo-1.2.3/priv/static/variants/default.js", _} ->
          {~c"lib/demo-1.2.3/priv/static/variants/default.js", "tampered"}

        entry ->
          entry
      end)

    tampered = Path.join(root, "tampered.wakecanvas")
    {:ok, _} = :zip.create(String.to_charlist(tampered), entries)
    assert {:error, :checksum_mismatch} = PackageArchive.validate(tampered)
  end

  test "rejects traversal before extraction", %{root: root} do
    archive = Path.join(root, "traversal.wakecanvas")

    {:ok, _} =
      :zip.create(String.to_charlist(archive), [
        {~c"wakecanvas-experience.json", Jason.encode!(manifest())},
        {~c"CHECKSUMS", ""},
        {~c"../escaped.txt", "no"}
      ])

    assert {:error, {:unsafe_path, "../escaped.txt"}} = PackageArchive.validate(archive)
    refute File.exists?(Path.join(root, "escaped.txt"))
  end

  test "rejects incompatible SDK requirements", %{root: root} do
    incompatible_manifest = manifest() |> Map.put("sdkRequirement", ">= 99.0.0")
    manifest_path = Path.join(root, "incompatible.json")
    File.write!(manifest_path, Jason.encode!(incompatible_manifest))
    incompatible = Path.join(root, "incompatible.wakecanvas")
    {:ok, _} = PackageBuilder.build(manifest_path, Path.join(root, "app"), incompatible)

    assert {:error, {:incompatible, "sdk", "0.1.0", ">= 99.0.0"}} =
             PackageArchive.validate(incompatible)
  end

  test "rejects a package for another target", %{root: root} do
    other_manifest = manifest() |> Map.put("target", "plan9-mips")
    manifest_path = Path.join(root, "other-target.json")
    File.write!(manifest_path, Jason.encode!(other_manifest))
    archive = Path.join(root, "other-target.wakecanvas")
    {:ok, _} = PackageBuilder.build(manifest_path, Path.join(root, "app"), archive)

    assert {:error, {:incompatible_target, _current, "plan9-mips"}} =
             PackageArchive.validate(archive)
  end

  test "rejects an invalid BEAM before staging", %{root: root} do
    app_path = Path.join(root, "app")
    File.write!(Path.join(app_path, "ebin/Elixir.Demo.beam"), "not a beam")
    archive = Path.join(root, "invalid-beam.wakecanvas")

    {:ok, _} =
      PackageBuilder.build(Path.join(root, "wakecanvas-experience.json"), app_path, archive)

    assert {:error, {:invalid_beam, "lib/demo-1.2.3/ebin/Elixir.Demo.beam"}} =
             PackageArchive.validate(archive)
  end

  test "rejects missing declared renderer assets", %{root: root} do
    missing =
      put_in(
        manifest(),
        ["displayVariants", Access.at(0), "entrypoint"],
        "static/variants/missing.js"
      )

    manifest_path = Path.join(root, "missing-renderer.json")
    File.write!(manifest_path, Jason.encode!(missing))
    archive = Path.join(root, "missing-renderer.wakecanvas")
    {:ok, _} = PackageBuilder.build(manifest_path, Path.join(root, "app"), archive)

    assert {:error, {:renderer_asset_missing, "static/variants/missing.js"}} =
             PackageArchive.validate(archive)
  end

  test "smoke-loads the compiled entry contract without installing it", context do
    source = """
    defmodule Demo do
      alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}

      def definition do
        %Definition{
          id: "org.example.demo",
          name: "Demo",
          version: "1.2.3",
          otp_application: :demo,
          stylesheet: "static/experience.css",
          surfaces: [
            %Surface{id: :display, path: "display", module: Demo, role: :display}
          ],
          default_display_variant: "default",
          display_variants: [
            %DisplayVariant{
              id: "default",
              label: "Default",
              description: "Smoke-test renderer",
              entrypoint: "static/variants/default.js"
            }
          ]
        }
      end

      def validate_config(config) when is_map(config), do: {:ok, config}
    end
    """

    [{Demo, bytes}] = Code.compile_string(source)
    File.write!(Path.join(context.app_path, "ebin/Elixir.Demo.beam"), bytes)
    archive = Path.join(context.root, "smoke.wakecanvas")

    {:ok, _} = PackageBuilder.build(context.manifest_path, context.app_path, archive)

    assert {:ok, result} = WakeCanvas.Experiences.PackageSmoke.verify(archive)
    assert result.experience_id == "org.example.demo"
    assert result.modules == 1
  end

  defp manifest do
    %{
      "manifestVersion" => 1,
      "experienceId" => "org.example.demo",
      "name" => "Demo",
      "version" => "1.2.3",
      "otpApplication" => "demo",
      "entryModule" => "Demo",
      "sdkRequirement" => ">= 0.1.0 and < 1.0.0",
      "platformRequirement" => ">= 0.1.0 and < 1.0.0",
      "elixirRequirement" => ">= 1.20.0 and < 2.0.0",
      "otpRequirement" => ">= 29.0.0 and < 30.0.0",
      "target" => "any",
      "surfaces" => [
        %{"id" => "display", "path" => "display", "module" => "Demo", "role" => "display"}
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
    }
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
