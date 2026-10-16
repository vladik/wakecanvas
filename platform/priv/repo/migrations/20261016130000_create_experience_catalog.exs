defmodule WakeCanvas.Repo.Migrations.CreateExperienceCatalog do
  use Ecto.Migration

  def change do
    create table(:experience_packages, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :version, :string, null: false
      add :status, :string, null: false, default: "installed"

      timestamps(type: :utc_datetime)
    end

    create table(:experience_instances) do
      add :experience_id,
          references(:experience_packages, column: :id, type: :string, on_delete: :restrict),
          null: false

      add :name, :string, null: false
      add :config, :map, null: false, default: %{}
      add :active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:experience_instances, [:experience_id])

    create unique_index(:experience_instances, [:active],
             where: "active = 1",
             name: :experience_instances_one_active_index
           )
  end
end
