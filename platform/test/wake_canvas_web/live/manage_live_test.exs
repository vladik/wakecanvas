defmodule WakeCanvasWeb.ManageLiveTest do
  use WakeCanvasWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Package
  alias WakeCanvas.Repo

  setup %{conn: conn} do
    package =
      Repo.insert!(%Package{
        id: "org.example.manage-#{System.unique_integer([:positive])}",
        name: "Manage Test Experience",
        version: "1.0.0",
        status: "installed"
      })

    {:ok, instance} =
      Experiences.create_instance(%{
        name: "Morning Workshop",
        slug: "morning-workshop",
        experience_id: package.id
      })

    conn = init_test_session(conn, %{"wakecanvas_management_access" => true})
    %{conn: conn, instance: instance}
  end

  test "management areas are separated into operator-facing tabs", %{conn: conn} do
    {:ok, _view, workshops_html} = live(conn, ~p"/manage")
    assert workshops_html =~ "Workshops"
    assert workshops_html =~ "Morning Workshop"
    assert workshops_html =~ "/i/morning-workshop/display"
    refute workshops_html =~ "Kiosk health"

    {:ok, _view, import_html} = live(conn, ~p"/manage/import")
    assert import_html =~ "Import workshop"
    refute import_html =~ "Morning Workshop"

    {:ok, _view, experiences_html} = live(conn, ~p"/manage/experiences")
    assert experiences_html =~ "Experience packages"
    assert experiences_html =~ "Manage Test Experience"

    {:ok, _view, system_html} = live(conn, ~p"/manage/system")
    assert system_html =~ "Kiosk health"
    refute system_html =~ "Create workshop"
  end

  test "an operator can rename a workshop without changing its Experience", %{
    conn: conn,
    instance: instance
  } do
    {:ok, view, _html} = live(conn, ~p"/manage")

    view
    |> element("button[phx-click='open_instance_details'][phx-value-id='#{instance.id}']")
    |> render_click()

    assert has_element?(view, "form[phx-submit='save_instance_details']")

    view
    |> form("form[phx-submit='save_instance_details']",
      edit_instance: %{name: "Evening Workshop", slug: "evening-workshop"}
    )
    |> render_submit()

    assert render(view) =~ "Evening Workshop"
    updated = Experiences.get_instance!(instance.id)
    assert updated.name == "Evening Workshop"
    assert updated.slug == "evening-workshop"
    assert updated.experience_id == instance.experience_id
  end

  test "participant QR destinations explain their purpose before the code", %{
    conn: conn,
    instance: instance
  } do
    {:ok, view, _html} = live(conn, ~p"/manage")

    assert has_element?(view, "#participant-qr-#{instance.id}", "Share with participants")

    assert has_element?(
             view,
             "#participant-qr-#{instance.id}-artwork",
             "Photograph or upload a finished artwork"
           )

    assert has_element?(
             view,
             "#participant-qr-#{instance.id}-moments",
             "Upload atmosphere and activity photos"
           )

    assert has_element?(
             view,
             "#participant-qr-#{instance.id}-messages",
             "Submit a short message or testimonial"
           )

    assert has_element?(
             view,
             "#participant-qr-#{instance.id}-artwork a[href='/i/morning-workshop/artwork']"
           )
  end
end
