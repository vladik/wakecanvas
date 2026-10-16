defmodule WakeCanvas.Experience.LivingGallery.StoreTest do
  use ExUnit.Case

  alias WakeCanvas.Experience.LivingGallery.Store

  test "stores and moderates media in an isolated instance database" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wakecanvas-store-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
      )

    database = Path.join(directory, "experience.sqlite")
    on_exit(fn -> File.rm_rf(directory) end)

    Store.insert(database, %{
      kind: "artwork",
      status: "pending",
      title: "Sun",
      creator_name: "Maya",
      show_attribution: true,
      filename: "sun.jpg",
      mime_type: "image/jpeg"
    })

    [item] = Store.list(database)
    assert item.title == "Sun"
    assert item.status == "pending"

    assert :ok = Store.set_status(database, item.id, "published")
    assert [%{status: "published"}] = Store.list(database, "published")

    assert :ok = Store.soft_delete(database, item.id)
    assert Store.list(database) == []
    assert [%{id: deleted_id, deleted_at: %DateTime{}}] = Store.list_deleted(database)
    assert deleted_id == item.id

    assert :ok = Store.restore(database, item.id)
    assert [%{id: restored_id, deleted_at: nil}] = Store.list(database)
    assert restored_id == item.id
  end
end
