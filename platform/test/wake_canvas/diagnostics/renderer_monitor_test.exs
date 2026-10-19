defmodule WakeCanvas.Diagnostics.RendererMonitorTest do
  use ExUnit.Case, async: false

  alias WakeCanvas.Diagnostics.RendererMonitor

  setup do
    RendererMonitor.clear()
    on_exit(fn -> RendererMonitor.clear() end)
    :ok
  end

  test "retains bounded renderer state and removes stopped clients" do
    instance_id = Ecto.UUID.generate()
    payload = valid_payload()

    assert :ok = RendererMonitor.report(instance_id, payload)
    assert [report] = RendererMonitor.snapshot(instance_id)
    assert report.client_id == payload["clientId"]
    assert report.active_variant == "gallery-orbit"
    assert report.fps == 59.5
    assert report.visible

    assert :ok = RendererMonitor.report(instance_id, Map.put(payload, "status", "stopped"))
    assert RendererMonitor.snapshot(instance_id) == []
  end

  test "ignores malformed and oversized browser reports" do
    instance_id = Ecto.UUID.generate()

    assert :ok = RendererMonitor.report(instance_id, %{"clientId" => String.duplicate("x", 65)})
    assert RendererMonitor.snapshot(instance_id) == []

    payload = valid_payload() |> Map.put("width", 100_000)
    assert :ok = RendererMonitor.report(instance_id, payload)
    assert RendererMonitor.snapshot(instance_id) == []
  end

  defp valid_payload do
    %{
      "clientId" => Ecto.UUID.generate(),
      "status" => "running",
      "requestedVariant" => "gallery-orbit",
      "activeVariant" => "gallery-orbit",
      "fallback" => false,
      "fallbackReason" => nil,
      "error" => nil,
      "width" => 1_920,
      "height" => 1_080,
      "devicePixelRatio" => 1.0,
      "fps" => 59.5,
      "visible" => true,
      "webgl2" => true
    }
  end
end
