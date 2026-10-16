defmodule WakeCanvas.Repo.Migrations.AddArchivedAtToExperienceInstances do
  use Ecto.Migration

  def change do
    alter table(:experience_instances) do
      add :archived_at, :utc_datetime
    end

    create index(:experience_instances, [:archived_at])
  end
end
