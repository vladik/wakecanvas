defmodule WakeCanvasWeb.MediaControllerTest do
  use WakeCanvasWeb.ConnCase

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.{InstancePaths, Package}
  alias WakeCanvas.Repo

  setup do
    Repo.get(Package, "org.wakecanvas.test-display") ||
      Repo.insert!(%Package{
        id: "org.wakecanvas.test-display",
        name: "Test Display",
        version: "1.0.0"
      })

    {:ok, instance} =
      Experiences.create_instance(%{
        name: "Media Workshop",
        experience_id: "org.wakecanvas.test-display"
      })

    InstancePaths.ensure!(instance.id)
    path = Path.join(InstancePaths.media_dir(instance.id), "sample.mp4")
    File.write!(path, "0123456789")

    on_exit(fn -> File.rm_rf(InstancePaths.data_dir(instance.id)) end)
    %{instance: instance}
  end

  test "serves a complete local media file with byte-range support", %{
    conn: conn,
    instance: instance
  } do
    conn = get(conn, "/media/instances/#{instance.id}/sample.mp4")

    assert response(conn, 200) == "0123456789"
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "content-type") |> List.first() =~ "video/mp4"
  end

  test "serves a requested media byte range", %{conn: conn, instance: instance} do
    conn =
      conn
      |> put_req_header("range", "bytes=2-5")
      |> get("/media/instances/#{instance.id}/sample.mp4")

    assert response(conn, 206) == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]
  end

  test "reports unsatisfiable media byte ranges", %{conn: conn, instance: instance} do
    conn =
      conn
      |> put_req_header("range", "bytes=20-")
      |> get("/media/instances/#{instance.id}/sample.mp4")

    assert response(conn, 416) == ""
    assert get_resp_header(conn, "content-range") == ["bytes */10"]
  end
end
