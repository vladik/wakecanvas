defmodule WakeCanvas.Experience.LivingGallery.Store do
  alias WakeCanvas.Experience.LivingGallery.{MediaItem, Repo}

  def list(database_path, status \\ nil) do
    with_repo(database_path, fn ->
      sql =
        if status,
          do:
            "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, inserted_at, deleted_at FROM media_items WHERE status = ? AND deleted_at IS NULL ORDER BY id DESC",
          else:
            "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, inserted_at, deleted_at FROM media_items WHERE deleted_at IS NULL ORDER BY id DESC"

      params = if status, do: [status], else: []
      %{rows: rows} = query!(sql, params)
      Enum.map(rows, &row_to_item/1)
    end)
  end

  def list_deleted(database_path) do
    with_repo(database_path, fn ->
      %{rows: rows} =
        query!(
          "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, inserted_at, deleted_at FROM media_items WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC"
        )

      Enum.map(rows, &row_to_item/1)
    end)
  end

  def insert(database_path, attrs) do
    with_repo(database_path, fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      query!(
        "INSERT INTO media_items (kind, status, title, creator_name, show_attribution, filename, mime_type, inserted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
          attrs.kind,
          attrs.status,
          blank_to_nil(attrs.title),
          blank_to_nil(attrs.creator_name),
          attrs.show_attribution,
          attrs.filename,
          attrs.mime_type,
          now
        ]
      )

      :ok
    end)
  end

  def set_status(database_path, id, status) when status in ["published", "unpublished"] do
    with_repo(database_path, fn ->
      query!("UPDATE media_items SET status = ? WHERE id = ?", [
        status,
        id
      ])

      :ok
    end)
  end

  def soft_delete(database_path, id) do
    with_repo(database_path, fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      query!("UPDATE media_items SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL", [
        now,
        id
      ])

      :ok
    end)
  end

  def restore(database_path, id) do
    with_repo(database_path, fn ->
      query!("UPDATE media_items SET deleted_at = NULL WHERE id = ?", [id])
      :ok
    end)
  end

  defp with_repo(database_path, fun) do
    File.mkdir_p!(Path.dirname(database_path))
    {:ok, repo} = Repo.start_link(database: database_path, pool_size: 1, name: nil)
    previous = Repo.put_dynamic_repo(repo)

    try do
      ensure_schema!()
      fun.()
    after
      Repo.put_dynamic_repo(previous)
      GenServer.stop(repo)
    end
  end

  defp ensure_schema! do
    query!("""
    CREATE TABLE IF NOT EXISTS media_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      status TEXT NOT NULL,
      title TEXT,
      creator_name TEXT,
      show_attribution INTEGER NOT NULL DEFAULT 0,
      filename TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      inserted_at TEXT NOT NULL
    )
    """)

    columns = query!("PRAGMA table_info(media_items)").rows

    unless Enum.any?(columns, fn [_cid, name | _rest] -> name == "deleted_at" end) do
      query!("ALTER TABLE media_items ADD COLUMN deleted_at TEXT")
    end

    query!("UPDATE media_items SET status = 'published' WHERE status = 'approved'")
    query!("UPDATE media_items SET status = 'unpublished' WHERE status = 'rejected'")
  end

  defp query!(sql, params \\ []),
    do: Ecto.Adapters.SQL.query!(Repo.get_dynamic_repo(), sql, params)

  defp row_to_item([
         id,
         kind,
         status,
         title,
         creator_name,
         show,
         filename,
         mime_type,
         inserted_at,
         deleted_at
       ]) do
    %MediaItem{
      id: id,
      kind: kind,
      status: status,
      title: title,
      creator_name: creator_name,
      show_attribution: show in [true, 1, "1"],
      filename: filename,
      mime_type: mime_type,
      inserted_at: parse_datetime(inserted_at),
      deleted_at: parse_datetime(deleted_at)
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, :missing_offset} ->
        {:ok, naive} = NaiveDateTime.from_iso8601(value)
        DateTime.from_naive!(naive, "Etc/UTC")
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
