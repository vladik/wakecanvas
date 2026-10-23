defmodule WakeCanvas.Experience.LivingGallery.Config do
  @moduledoc false

  @defaults %{
    "artwork_auto_publish" => true,
    "moments_auto_publish" => false,
    "messages_auto_publish" => false,
    "retain_originals" => true,
    "presentation_label" => "Living Gallery",
    "presentation_title" => "",
    "presentation_description" => "",
    "display_variant" => "living-collage"
  }

  def defaults, do: @defaults
  def with_defaults(config) when is_map(config), do: Map.merge(@defaults, config)

  def auto_publish?(config, "artwork"),
    do: Map.get(with_defaults(config), "artwork_auto_publish") == true

  def auto_publish?(config, "workshop_moment"),
    do: Map.get(with_defaults(config), "moments_auto_publish") == true

  def auto_publish?(config, "message"),
    do: Map.get(with_defaults(config), "messages_auto_publish") == true

  def retain_originals?(config),
    do: Map.get(with_defaults(config), "retain_originals") == true
end
