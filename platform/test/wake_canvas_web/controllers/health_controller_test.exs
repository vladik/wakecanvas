defmodule WakeCanvasWeb.HealthControllerTest do
  use WakeCanvasWeb.ConnCase, async: false

  alias WakeCanvas.Experiences.Instance
  alias WakeCanvas.Repo

  setup do
    Repo.update_all(Instance, set: [active: false])
    :ok
  end

  test "health is available without a management session and omits private details", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert conn.status in [200, 503]
    body = Jason.decode!(response(conn, conn.status))

    # The build host can legitimately be below the configured free-disk limit.
    assert body["status"] in ["ok", "warning", "error"]
    assert conn.status == if(body["status"] == "error", do: 503, else: 200)
    assert is_binary(body["platform_version"])
    assert is_integer(body["uptime_seconds"])
    assert Enum.any?(body["checks"], &(&1["id"] == "platform_database"))
    refute Enum.any?(body["checks"], &Map.has_key?(&1, "details"))
  end
end
