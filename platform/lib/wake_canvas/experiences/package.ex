defmodule WakeCanvas.Experiences.Package do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "experience_packages" do
    field :name, :string
    field :version, :string
    field :status, :string, default: "installed"

    has_many :instances, WakeCanvas.Experiences.Instance, foreign_key: :experience_id

    timestamps(type: :utc_datetime)
  end

  def changeset(package, attrs) do
    package
    |> cast(attrs, [:id, :name, :version, :status])
    |> validate_required([:id, :name, :version, :status])
  end
end
