defmodule WakeCanvas.Repo.Migrations.ConvertInstanceIdsToUuid do
  use Ecto.Migration

  def up do
    execute(fn ->
      columns = repo().query!("PRAGMA table_info(experience_instances)").rows

      case Enum.find(columns, fn [_cid, name | _rest] -> name == "id" end) do
        [_cid, _name, type | _rest] when type in ["INTEGER", "integer"] ->
          convert_integer_instances!()

        _already_uuid ->
          :ok
      end
    end)
  end

  def down do
    raise "instance UUIDs are permanent and cannot be converted back to local integers"
  end

  defp convert_integer_instances! do
    rows =
      repo().query!("""
      SELECT id, experience_id, name, config, active, archived_at, inserted_at, updated_at
      FROM experience_instances
      ORDER BY id
      """).rows

    instances =
      Enum.map(rows, fn [
                          old_id,
                          experience_id,
                          name,
                          config,
                          active,
                          archived_at,
                          inserted_at,
                          updated_at
                        ] ->
        %{
          old_id: old_id,
          id: Ecto.UUID.generate(),
          experience_id: experience_id,
          name: name,
          config: config,
          active: active,
          archived_at: archived_at,
          inserted_at: inserted_at,
          updated_at: updated_at
        }
      end)

    repo().query!("""
    CREATE TABLE experience_instances_uuid (
      id TEXT PRIMARY KEY NOT NULL,
      experience_id TEXT NOT NULL REFERENCES experience_packages(id) ON DELETE RESTRICT,
      name TEXT NOT NULL,
      slug TEXT,
      config TEXT NOT NULL DEFAULT '{}',
      active INTEGER NOT NULL DEFAULT 0,
      archived_at TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    Enum.each(instances, fn instance ->
      repo().query!(
        """
        INSERT INTO experience_instances_uuid
          (id, experience_id, name, slug, config, active, archived_at, inserted_at, updated_at)
        VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?)
        """,
        [
          instance.id,
          instance.experience_id,
          instance.name,
          instance.config,
          instance.active,
          instance.archived_at,
          instance.inserted_at,
          instance.updated_at
        ]
      )
    end)

    repo().query!("DROP TABLE experience_instances")
    repo().query!("ALTER TABLE experience_instances_uuid RENAME TO experience_instances")

    repo().query!(
      "CREATE INDEX experience_instances_experience_id_index ON experience_instances (experience_id)"
    )

    repo().query!(
      "CREATE UNIQUE INDEX experience_instances_slug_index ON experience_instances (slug) WHERE slug IS NOT NULL"
    )

    repo().query!(
      "CREATE UNIQUE INDEX experience_instances_one_active_index ON experience_instances (active) WHERE active = 1"
    )

    repo().query!(
      "CREATE INDEX experience_instances_archived_at_index ON experience_instances (archived_at)"
    )

    move_instance_directories!(instances)
  end

  defp move_instance_directories!(instances) do
    root = Application.fetch_env!(:wake_canvas, :data_root) |> Path.join("instances")

    Enum.reduce_while(instances, [], fn instance, moved ->
      source = Path.join(root, Integer.to_string(instance.old_id))
      target = Path.join(root, instance.id)

      cond do
        not File.exists?(source) ->
          {:cont, moved}

        File.exists?(target) ->
          rollback_moves!(moved)
          raise "cannot migrate instance #{instance.old_id}: UUID destination already exists"

        true ->
          case File.rename(source, target) do
            :ok ->
              {:cont, [{target, source} | moved]}

            {:error, reason} ->
              rollback_moves!(moved)

              raise "cannot migrate instance #{instance.old_id} data directory: #{inspect(reason)}"
          end
      end
    end)

    :ok
  end

  defp rollback_moves!(moves) do
    Enum.each(moves, fn {current, original} ->
      case File.rename(current, original) do
        :ok ->
          :ok

        {:error, reason} ->
          raise "failed to roll back instance directory migration: #{inspect(reason)}"
      end
    end)
  end
end
