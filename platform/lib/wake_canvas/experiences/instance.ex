defmodule WakeCanvas.Experiences.Instance do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "experience_instances" do
    field :name, :string
    field :slug, :string
    field :config, :map, default: %{}
    field :active, :boolean, default: false
    field :archived_at, :utc_datetime
    field :participant_code_digest, :string, redact: true
    field :participant_code_version, :integer, default: 0

    belongs_to :package, WakeCanvas.Experiences.Package,
      foreign_key: :experience_id,
      references: :id,
      type: :string

    timestamps(type: :utc_datetime)
  end

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [:name, :slug, :experience_id, :config])
    |> validate_details()
    |> validate_required([:experience_id])
    |> foreign_key_constraint(:experience_id)
  end

  def details_changeset(instance, attrs) do
    instance
    |> cast(attrs, [:name, :slug])
    |> validate_details()
  end

  defp validate_details(changeset) do
    changeset
    |> update_change(:slug, &normalize_slug/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_length(:slug, min: 2, max: 60)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must contain lowercase letters, numbers, and single hyphens only"
    )
    |> unique_constraint(:slug)
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(slug) do
    case slug |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> normalized
    end
  end
end
