defmodule WakeCanvas.Experience.LivingGallery.Store do
  alias WakeCanvas.Experience.LivingGallery.{MediaItem, Message, Repo}

  def migrate(database_path) do
    with_raw_repo(database_path, fn ->
      ensure_schema!()
      :ok
    end)
  end

  def list_messages(database_path, status \\ nil) do
    with_repo(database_path, fn ->
      {where, params} =
        if status,
          do: {"status = ? AND deleted_at IS NULL", [status]},
          else: {"deleted_at IS NULL", []}

      %{rows: rows} =
        query!(
          "SELECT id, status, body, author_name, show_attribution, inserted_at, deleted_at FROM messages WHERE #{where} ORDER BY id DESC",
          params
        )

      Enum.map(rows, &row_to_message/1)
    end)
  end

  def list_deleted_messages(database_path) do
    with_repo(database_path, fn ->
      %{rows: rows} =
        query!(
          "SELECT id, status, body, author_name, show_attribution, inserted_at, deleted_at FROM messages WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC"
        )

      Enum.map(rows, &row_to_message/1)
    end)
  end

  def insert_message(database_path, attrs) do
    with_write_repo(database_path, fn ->
      query!(
        "INSERT INTO messages (status, body, author_name, show_attribution, inserted_at) VALUES (?, ?, ?, ?, ?)",
        [
          attrs.status,
          attrs.body,
          attrs.author_name,
          attrs.show_attribution,
          DateTime.utc_now() |> DateTime.truncate(:second)
        ]
      )

      :ok
    end)
  end

  def set_message_status(database_path, id, status) when status in ["published", "unpublished"] do
    with_write_repo(database_path, fn ->
      query!("UPDATE messages SET status = ? WHERE id = ?", [status, id])
      :ok
    end)
  end

  def soft_delete_message(database_path, id) do
    with_write_repo(database_path, fn ->
      query!("UPDATE messages SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL", [
        DateTime.utc_now() |> DateTime.truncate(:second),
        id
      ])

      :ok
    end)
  end

  def restore_message(database_path, id) do
    with_write_repo(database_path, fn ->
      query!("UPDATE messages SET deleted_at = NULL WHERE id = ?", [id])
      :ok
    end)
  end

  def purge_message(database_path, id) do
    with_write_repo(database_path, fn ->
      case query!("SELECT id FROM messages WHERE id = ? AND deleted_at IS NOT NULL", [id]).rows do
        [[^id]] ->
          query!("DELETE FROM messages WHERE id = ?", [id])
          :ok

        [] ->
          {:error, :not_deleted}
      end
    end)
  end

  def list(database_path, status \\ nil) do
    with_repo(database_path, fn ->
      sql =
        if status,
          do:
            "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, original_filename, original_mime_type, inserted_at, deleted_at FROM media_items WHERE status = ? AND deleted_at IS NULL ORDER BY id DESC",
          else:
            "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, original_filename, original_mime_type, inserted_at, deleted_at FROM media_items WHERE deleted_at IS NULL ORDER BY id DESC"

      params = if status, do: [status], else: []
      %{rows: rows} = query!(sql, params)
      Enum.map(rows, &row_to_item/1)
    end)
  end

  def list_deleted(database_path) do
    with_repo(database_path, fn ->
      %{rows: rows} =
        query!(
          "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, original_filename, original_mime_type, inserted_at, deleted_at FROM media_items WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC"
        )

      Enum.map(rows, &row_to_item/1)
    end)
  end

  def insert(database_path, attrs) do
    with_write_repo(database_path, fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      query!(
        "INSERT INTO media_items (kind, status, title, creator_name, show_attribution, filename, mime_type, original_filename, original_mime_type, inserted_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          attrs.kind,
          attrs.status,
          blank_to_nil(attrs.title),
          blank_to_nil(attrs.creator_name),
          attrs.show_attribution,
          attrs.filename,
          attrs.mime_type,
          Map.get(attrs, :original_filename),
          Map.get(attrs, :original_mime_type),
          now
        ]
      )

      :ok
    end)
  end

  def set_status(database_path, id, status) when status in ["published", "unpublished"] do
    with_write_repo(database_path, fn ->
      query!("UPDATE media_items SET status = ? WHERE id = ?", [
        status,
        id
      ])

      :ok
    end)
  end

  def update_metadata(database_path, id, attrs) do
    with_write_repo(database_path, fn ->
      query!(
        "UPDATE media_items SET title = ?, creator_name = ?, show_attribution = ? WHERE id = ? AND deleted_at IS NULL",
        [
          attrs.title |> normalize_text(120) |> blank_to_nil(),
          attrs.creator_name |> normalize_text(80) |> blank_to_nil(),
          if(attrs.show_attribution == true, do: 1, else: 0),
          id
        ]
      )

      :ok
    end)
  end

  def soft_delete(database_path, id) do
    with_write_repo(database_path, fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      query!("UPDATE media_items SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL", [
        now,
        id
      ])

      :ok
    end)
  end

  def restore(database_path, id) do
    with_write_repo(database_path, fn ->
      query!("UPDATE media_items SET deleted_at = NULL WHERE id = ?", [id])
      :ok
    end)
  end

  def purge(database_path, id) do
    with_write_repo(database_path, fn ->
      case query!(
             "SELECT id, kind, status, title, creator_name, show_attribution, filename, mime_type, original_filename, original_mime_type, inserted_at, deleted_at FROM media_items WHERE id = ? AND deleted_at IS NOT NULL",
             [id]
           ).rows do
        [row] ->
          item = row_to_item(row)
          query!("DELETE FROM media_items WHERE id = ? AND deleted_at IS NOT NULL", [id])
          {:ok, item}

        [] ->
          {:error, :not_deleted}
      end
    end)
  end

  defp with_write_repo(database_path, fun) do
    resource = {__MODULE__, Path.expand(database_path)}

    :global.trans({resource, self()}, fn ->
      with_repo(database_path, fun)
    end)
  end

  defp with_repo(database_path, fun) do
    with_raw_repo(database_path, fn ->
      ensure_schema!()
      fun.()
    end)
  end

  defp with_raw_repo(database_path, fun) do
    File.mkdir_p!(Path.dirname(database_path))

    {:ok, repo} =
      Repo.start_link(
        database: database_path,
        pool_size: 1,
        name: nil,
        journal_mode: :wal,
        busy_timeout: 10_000
      )

    previous = Repo.put_dynamic_repo(repo)

    try do
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
      original_filename TEXT,
      original_mime_type TEXT,
      inserted_at TEXT NOT NULL,
      deleted_at TEXT
    )
    """)

    query!("""
    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      status TEXT NOT NULL,
      body TEXT NOT NULL,
      author_name TEXT,
      show_attribution INTEGER NOT NULL DEFAULT 0,
      inserted_at TEXT NOT NULL,
      deleted_at TEXT
    )
    """)

    columns = query!("PRAGMA table_info(media_items)").rows

    unless Enum.any?(columns, fn [_cid, name | _rest] -> name == "deleted_at" end) do
      add_deleted_at_column()
    end

    unless Enum.any?(columns, fn [_cid, name | _rest] -> name == "original_filename" end) do
      add_column("original_filename", "TEXT")
    end

    unless Enum.any?(columns, fn [_cid, name | _rest] -> name == "original_mime_type" end) do
      add_column("original_mime_type", "TEXT")
    end

    query!("UPDATE media_items SET status = 'published' WHERE status = 'approved'")
    query!("UPDATE media_items SET status = 'unpublished' WHERE status = 'rejected'")
  end

  defp add_deleted_at_column do
    add_column("deleted_at", "TEXT")
  end

  defp add_column(name, type) do
    query!("ALTER TABLE media_items ADD COLUMN #{name} #{type}")
  rescue
    error in Exqlite.Error ->
      if String.contains?(Exception.message(error), "duplicate column name"),
        do: :ok,
        else: reraise(error, __STACKTRACE__)
  end

  defp query!(sql, params \\ []), do: query_with_retry!(sql, params, 0)

  defp query_with_retry!(sql, params, attempt) do
    case Ecto.Adapters.SQL.query(Repo.get_dynamic_repo(), sql, params) do
      {:ok, result} ->
        result

      {:error, error} when attempt < 3 ->
        if transient_busy?(error) do
          Process.sleep(25 * Integer.pow(2, attempt))
          query_with_retry!(sql, params, attempt + 1)
        else
          raise error
        end

      {:error, error} ->
        raise error
    end
  end

  defp transient_busy?(error) do
    message = Exception.message(error)
    String.contains?(message, ["database is locked", "database is busy", "SQLITE_BUSY"])
  end

  defp row_to_item([
         id,
         kind,
         status,
         title,
         creator_name,
         show,
         filename,
         mime_type,
         original_filename,
         original_mime_type,
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
      original_filename: original_filename,
      original_mime_type: original_mime_type,
      inserted_at: parse_datetime(inserted_at),
      deleted_at: parse_datetime(deleted_at)
    }
  end

  defp row_to_message([id, status, body, author_name, show, inserted_at, deleted_at]) do
    %Message{
      id: id,
      status: status,
      body: body,
      author_name: author_name,
      show_attribution: show in [true, 1, "1"],
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

  defp normalize_text(value, max) when is_binary(value),
    do: value |> String.trim() |> String.slice(0, max)

  defp normalize_text(_value, _max), do: ""
end
