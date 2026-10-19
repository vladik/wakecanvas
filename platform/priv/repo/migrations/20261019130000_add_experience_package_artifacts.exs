defmodule WakeCanvas.Repo.Migrations.AddExperiencePackageArtifacts do
  use Ecto.Migration

  def change do
    alter table(:experience_packages) do
      add :archive_digest, :string
      add :previous_archive_digest, :string
      add :manifest, :map, null: false, default: %{}
    end

    create index(:experience_packages, [:archive_digest])
  end
end
