defmodule WakeCanvas.Repo.Migrations.AddPreviousPackageManifest do
  use Ecto.Migration

  def change do
    alter table(:experience_packages) do
      add :previous_manifest, :map
    end
  end
end
