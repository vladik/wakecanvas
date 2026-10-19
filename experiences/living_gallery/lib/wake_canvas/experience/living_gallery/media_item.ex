defmodule WakeCanvas.Experience.LivingGallery.MediaItem do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "media_items" do
    field(:kind, :string)
    field(:status, :string)
    field(:title, :string)
    field(:creator_name, :string)
    field(:show_attribution, :boolean)
    field(:filename, :string)
    field(:mime_type, :string)
    field(:original_filename, :string)
    field(:original_mime_type, :string)
    field(:inserted_at, :utc_datetime)
    field(:deleted_at, :utc_datetime)
  end
end
