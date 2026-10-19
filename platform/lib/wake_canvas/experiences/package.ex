defmodule WakeCanvas.Experiences.Package do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "experience_packages" do
    field :name, :string
    field :version, :string
    field :status, :string, default: "installed"
    field :archive_digest, :string
    field :previous_archive_digest, :string
    field :manifest, :map, default: %{}
    field :previous_manifest, :map
    field :diagnostic, :string

    has_many :instances, WakeCanvas.Experiences.Instance, foreign_key: :experience_id

    timestamps(type: :utc_datetime)
  end

  def changeset(package, attrs) do
    package
    |> cast(attrs, [
      :id,
      :name,
      :version,
      :status,
      :archive_digest,
      :previous_archive_digest,
      :manifest,
      :previous_manifest,
      :diagnostic
    ])
    |> validate_required([:id, :name, :version, :status])
    |> validate_inclusion(:status, ["installed", "pending_restart", "rejected"])
  end
end
