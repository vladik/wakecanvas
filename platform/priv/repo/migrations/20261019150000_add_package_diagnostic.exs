defmodule WakeCanvas.Repo.Migrations.AddPackageDiagnostic do
  use Ecto.Migration

  def change do
    alter table(:experience_packages) do
      add :diagnostic, :string
    end
  end
end
