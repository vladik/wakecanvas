defmodule WakeCanvas.Experience.LivingGallery.Message do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "messages" do
    field(:status, :string)
    field(:body, :string)
    field(:author_name, :string)
    field(:show_attribution, :boolean)
    field(:inserted_at, :utc_datetime)
    field(:deleted_at, :utc_datetime)
  end
end
