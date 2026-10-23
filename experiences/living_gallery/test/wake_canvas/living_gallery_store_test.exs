defmodule WakeCanvas.Experience.LivingGallery.StoreTest do
  use ExUnit.Case

  alias WakeCanvas.Experience.LivingGallery.{Repo, Store}

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
      mime_type: "image/jpeg",
      original_filename: "sun-original.jpg",
      original_mime_type: "image/jpeg"
    })

    [item] = Store.list(database)
    assert item.title == "Sun"
    assert item.status == "pending"
    assert item.original_filename == "sun-original.jpg"
    assert item.original_mime_type == "image/jpeg"

    assert :ok =
             Store.update_metadata(database, item.id, %{
               title: "  Brighter Sun  ",
               creator_name: "Alex",
               show_attribution: true
             })

    assert [%{title: "Brighter Sun", creator_name: "Alex", show_attribution: true}] =
             Store.list(database)

    assert :ok = Store.set_status(database, item.id, "published")
    assert [%{status: "published"}] = Store.list(database, "published")

    assert :ok = Store.soft_delete(database, item.id)
    assert Store.list(database) == []
    assert [%{id: deleted_id, deleted_at: %DateTime{}}] = Store.list_deleted(database)
    assert deleted_id == item.id

    assert :ok = Store.restore(database, item.id)
    assert [%{id: restored_id, deleted_at: nil}] = Store.list(database)
    assert restored_id == item.id

    assert {:error, :not_deleted} = Store.purge(database, item.id)
    assert :ok = Store.soft_delete(database, item.id)
    assert {:ok, %{id: purged_id}} = Store.purge(database, item.id)
    assert purged_id == item.id
    assert Store.list_deleted(database) == []
  end

  test "accepts a burst of ten concurrent inserts without exposing SQLite busy errors" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wakecanvas-burst-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
      )

    database = Path.join(directory, "experience.sqlite")
    on_exit(fn -> File.rm_rf(directory) end)

    results =
      1..10
      |> Task.async_stream(
        fn number ->
          Store.insert(database, %{
            kind: "artwork",
            status: "published",
            title: "Artwork #{number}",
            creator_name: nil,
            show_attribution: false,
            filename: "artwork-#{number}.png",
            mime_type: "image/png"
          })
        end,
        max_concurrency: 10,
        ordered: false,
        timeout: 20_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, :ok}, &1))
    assert Store.list(database) |> length() == 10
  end

  test "stores, moderates, restores, and purges visitor messages" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wakecanvas-messages-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
      )

    database = Path.join(directory, "experience.sqlite")
    on_exit(fn -> File.rm_rf(directory) end)

    assert :ok =
             Store.insert_message(database, %{
               status: "pending",
               body: "We made this together.",
               author_name: "Maya",
               show_attribution: true
             })

    assert [%{id: id, status: "pending", body: "We made this together."}] =
             Store.list_messages(database)

    assert :ok = Store.set_message_status(database, id, "published")
    assert [%{id: ^id}] = Store.list_messages(database, "published")
    assert :ok = Store.soft_delete_message(database, id)
    assert [] = Store.list_messages(database)
    assert [%{id: ^id}] = Store.list_deleted_messages(database)
    assert :ok = Store.restore_message(database, id)
    assert [%{id: ^id}] = Store.list_messages(database)
    assert {:error, :not_deleted} = Store.purge_message(database, id)
    assert :ok = Store.soft_delete_message(database, id)
    assert :ok = Store.purge_message(database, id)
    assert [] = Store.list_deleted_messages(database)
  end

  test "upgrades an existing instance database without losing media" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "wakecanvas-legacy-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
      )

    database = Path.join(directory, "experience.sqlite")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, repo} = Repo.start_link(database: database, pool_size: 1, name: nil)

    Ecto.Adapters.SQL.query!(repo, """
    CREATE TABLE media_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      status TEXT NOT NULL,
      title TEXT,
      creator_name TEXT,
      show_attribution INTEGER NOT NULL DEFAULT 0,
      filename TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      deleted_at TEXT
    )
    """)

    Ecto.Adapters.SQL.query!(
      repo,
      "INSERT INTO media_items (kind, status, filename, mime_type, inserted_at) VALUES (?, ?, ?, ?, ?)",
      ["artwork", "published", "legacy.png", "image/png", "2026-10-19T12:00:00Z"]
    )

    GenServer.stop(repo)

    assert [%{filename: "legacy.png", original_filename: nil, original_mime_type: nil}] =
             Store.list(database)
  end
end
