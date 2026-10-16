defmodule WakeCanvasWeb.SurfaceControllerTest do
  use WakeCanvasWeb.ConnCase

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Package
  alias WakeCanvas.Repo

  setup do
    Repo.insert!(%Package{
      id: "org.wakecanvas.test-display",
      name: "Test Display",
      version: "1.0.0"
    })

    {:ok, instance} =
      Experiences.create_instance(%{
        name: "Variant Workshop",
        experience_id: "org.wakecanvas.test-display"
      })

    %{instance: instance}
  end

  test "uses the declared default and accepts a valid URL override", %{
    conn: conn,
    instance: instance
  } do
    assert conn
           |> get("/i/#{instance.id}/display")
           |> html_response(200) =~ "Variant: default"

    assert build_conn()
           |> get("/i/#{instance.id}/display?variant=alternate")
           |> html_response(200) =~ "Variant: alternate"
  end

  test "rejects an unknown explicit variant", %{conn: conn, instance: instance} do
    assert conn
           |> get("/i/#{instance.id}/display?variant=missing")
           |> response(404) == "Experience surface not found"
  end

  test "falls back safely when a saved variant no longer exists", %{
    conn: conn,
    instance: instance
  } do
    {:ok, _instance} =
      Experiences.update_instance_config(instance, %{"display_variant" => "removed-by-upgrade"})

    assert conn
           |> get("/i/#{instance.id}/display")
           |> html_response(200) =~ "Variant: default"
  end
end
