defmodule WakeCanvasWeb.SurfaceControllerTest do
  use WakeCanvasWeb.ConnCase

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Package
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
        name: "Variant Workshop",
        experience_id: "org.wakecanvas.test-display"
      })

    %{instance: instance}
  end

  test "uses the declared default and accepts an explicit variant route", %{
    conn: conn,
    instance: instance
  } do
    assert conn
           |> get("/i/#{instance.id}/display")
           |> html_response(200) =~ "Variant: default"

    assert build_conn()
           |> get("/i/#{instance.id}/display/alternate")
           |> html_response(200) =~ "Variant: alternate"
  end

  test "rejects an unknown explicit variant", %{conn: conn, instance: instance} do
    assert conn
           |> get("/i/#{instance.id}/display/missing")
           |> response(404) == "Experience surface not found"
  end

  test "does not crash when a development reload leaves an older variant descriptor", %{
    conn: conn,
    instance: instance
  } do
    assert conn
           |> get("/i/#{instance.id}/display/legacy")
           |> html_response(200) =~ "Variant: legacy"
  end

  test "accepts a configured slug as a URL alias", %{conn: conn, instance: instance} do
    {:ok, instance} =
      instance
      |> WakeCanvas.Experiences.Instance.changeset(%{slug: "variant-workshop"})
      |> Repo.update()

    assert conn
           |> get("/i/#{instance.slug}/display")
           |> html_response(200) =~ "Variant: default"
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

  test "serves executable Experience assets outside the CSRF browser pipeline", %{conn: conn} do
    conn =
      get(
        conn,
        "/experience-assets/org.wakecanvas.test-display/static/assets/js/app.js"
      )

    assert response(conn, 200) =~ "LiveSocket"
    assert get_resp_header(conn, "content-type") |> List.first() =~ "javascript"
  end
end
