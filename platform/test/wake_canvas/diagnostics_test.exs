defmodule WakeCanvas.DiagnosticsTest do
  use WakeCanvas.DataCase, async: false

  alias WakeCanvas.Diagnostics
  alias WakeCanvas.Diagnostics.RendererMonitor
  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.{InstancePaths, Package}
  alias WakeCanvas.Repo

  setup do
    root =
      Path.join(System.tmp_dir!(), "wakecanvas-diagnostics-#{System.unique_integer([:positive])}")

    original_root = Application.fetch_env!(:wake_canvas, :data_root)
    Application.put_env(:wake_canvas, :data_root, root)
    RendererMonitor.clear()
    Repo.update_all(WakeCanvas.Experiences.Instance, set: [active: false])

    on_exit(fn ->
      Application.put_env(:wake_canvas, :data_root, original_root)
      RendererMonitor.clear()
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "reports platform integrity and bounded instance storage", %{root: root} do
    package =
      Repo.insert!(%Package{
        id: "org.example.diagnostics-#{System.unique_integer([:positive])}",
        name: "Diagnostic Experience",
        version: "1.0.0"
      })

    {:ok, instance} =
      Experiences.create_instance(%{name: "Diagnostic Workshop", experience_id: package.id})

    InstancePaths.ensure!(instance.id)
    File.write!(Path.join(InstancePaths.media_dir(instance.id), "sample.bin"), "12345678")

    report = Diagnostics.snapshot()
    checks = Map.new(report.checks, &{&1.id, &1})

    # Host disk pressure is intentionally allowed to make the aggregate report
    # an error; assertions below verify the deterministic checks under test.
    assert report.status in [:ok, :warning, :error]
    assert checks.platform_database.status == :ok
    assert checks.data_directory.status == :ok
    assert checks.instance_storage.status == :ok
    assert checks.instance_storage.details.instances >= 1
    assert checks.instance_storage.details.files == 1
    assert checks.instance_storage.details.bytes == 8
    assert checks.data_directory.details.path == Path.expand(root)
  end

  test "public status omits diagnostic details and local filesystem paths", %{root: root} do
    report = Diagnostics.public_snapshot()
    encoded = Jason.encode!(report)

    assert report.status in [:ok, :warning, :error]
    assert Enum.all?(report.checks, &(Map.keys(&1) |> Enum.sort() == [:id, :message, :status]))
    refute encoded =~ Path.expand(root)
  end

  test "classifies renderer fallback and failure for the active instance" do
    package =
      Repo.insert!(%Package{
        id: "org.example.renderer-health-#{System.unique_integer([:positive])}",
        name: "Renderer Health",
        version: "1.0.0"
      })

    {:ok, instance} =
      Experiences.create_instance(%{name: "Renderer Workshop", experience_id: package.id})

    instance |> Ecto.Changeset.change(active: true) |> Repo.update!()

    payload = %{
      "clientId" => Ecto.UUID.generate(),
      "status" => "running",
      "requestedVariant" => "gallery-orbit",
      "activeVariant" => "community-tapestry",
      "fallback" => true,
      "fallbackReason" => "Unsupported capabilities: webgl2",
      "error" => nil,
      "width" => 1_920,
      "height" => 1_080,
      "devicePixelRatio" => 1.0,
      "fps" => 60.0,
      "visible" => true,
      "webgl2" => false
    }

    RendererMonitor.report(instance.id, payload)
    renderer = Diagnostics.snapshot().checks |> Enum.find(&(&1.id == :renderer))
    assert renderer.status == :warning
    assert renderer.details.fallback

    RendererMonitor.report(
      instance.id,
      payload
      |> Map.put("status", "error")
      |> Map.put("fallback", false)
      |> Map.put("error", "mount failed")
    )

    renderer = Diagnostics.snapshot().checks |> Enum.find(&(&1.id == :renderer))
    assert renderer.status == :error
  end
end
