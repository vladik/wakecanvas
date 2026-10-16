defmodule WakeCanvas.Experiences.Instance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "experience_instances" do
    field :name, :string
    field :config, :map, default: %{}
    field :active, :boolean, default: false
    field :archived_at, :utc_datetime

    belongs_to :package, WakeCanvas.Experiences.Package,
      foreign_key: :experience_id,
      references: :id,
      type: :string

    timestamps(type: :utc_datetime)
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [:name, :experience_id, :config])
    |> validate_required([:name, :experience_id])
    |> validate_length(:name, min: 2, max: 80)
    |> foreign_key_constraint(:experience_id)
  end
end
