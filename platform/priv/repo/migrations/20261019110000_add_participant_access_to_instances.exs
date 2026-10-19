defmodule WakeCanvas.Repo.Migrations.AddParticipantAccessToInstances do
  use Ecto.Migration

  def change do
    alter table(:experience_instances) do
      add :participant_code_digest, :string
      add :participant_code_version, :integer, null: false, default: 0
    end
  end
end
