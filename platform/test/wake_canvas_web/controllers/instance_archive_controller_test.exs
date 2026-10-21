defmodule WakeCanvasWeb.InstanceArchiveControllerTest do
  use WakeCanvasWeb.ConnCase, async: false

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.{InstancePaths, Package}
  alias WakeCanvas.Repo

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "wakecanvas-export-controller-#{System.unique_integer([:positive])}"
      )

    original_root = Application.fetch_env!(:wake_canvas, :data_root)
    Application.put_env(:wake_canvas, :data_root, root)

    package =
      Repo.insert!(%Package{
        id: "org.example.export-controller-#{System.unique_integer([:positive])}",
        name: "Export Controller",
        version: "1.0.0"
      })

    {:ok, instance} =
      Experiences.create_instance(%{name: "Portable Day", experience_id: package.id})

    InstancePaths.ensure!(instance.id)
    File.write!(InstancePaths.database_path(instance.id), "database")

    on_exit(fn ->
      Application.put_env(:wake_canvas, :data_root, original_root)
      File.rm_rf!(root)
    end)

    %{instance: instance, root: root}
  end

  test "management downloads an active-list instance without archiving it", %{
    conn: conn,
    instance: instance,
    root: root
  } do
    conn =
      conn
      |> init_test_session(%{"wakecanvas_management_access" => true})
      |> get(~p"/manage/instances/#{instance.id}/export")

    assert response(conn, 200) =~ "PK"
    assert get_resp_header(conn, "content-type") == ["application/vnd.wakecanvas.instance+zip"]

    assert get_resp_header(conn, "content-disposition") |> hd() =~
             "portable-day.wakecanvas-instance"

    assert is_nil(Experiences.get_instance!(instance.id).archived_at)
    assert File.ls!(Path.join(root, "exports")) == []
  end
end
