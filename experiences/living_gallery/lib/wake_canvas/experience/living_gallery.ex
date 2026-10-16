defmodule WakeCanvas.Experience.LivingGallery do
  @moduledoc """
  WakeCanvas Experience for participatory art workshops.

  Workshop photographs form an ambient moving collage while submitted artwork is
  introduced prominently and retained in a separate rotating gallery.
  """

  @behaviour WakeCanvas.ExperienceSDK.Experience

  alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}

  @impl true
  def definition do
    %Definition{
      id: "org.wakecanvas.experience.living-gallery",
      name: "Living Gallery",
      version: "0.1.0",
      otp_application: :wake_canvas_experience_living_gallery,
      surfaces: [
        %Surface{
          id: :display,
          path: "display",
          module: WakeCanvas.Experience.LivingGallery.DisplayLive,
          role: :display,
          label: "Living Gallery Wall"
        },
        %Surface{
          id: :artwork,
          path: "artwork",
          module: WakeCanvas.Experience.LivingGallery.ArtworkIntakeLive,
          role: :primary_intake,
          label: "Add an Artwork"
        },
        %Surface{
          id: :moments,
          path: "moments",
          module: WakeCanvas.Experience.LivingGallery.MomentsUploadLive,
          role: :participant,
          label: "Workshop Moments"
        },
        %Surface{
          id: :review,
          path: "review",
          module: WakeCanvas.Experience.LivingGallery.ReviewLive,
          role: :operator,
          label: "Review Submissions"
        },
        %Surface{
          id: :settings,
          path: "settings",
          module: WakeCanvas.Experience.LivingGallery.SettingsLive,
          role: :operator,
          label: "Living Gallery Settings"
        }
      ],
      capabilities: [:camera, :participant_devices],
      default_display_variant: "living-collage",
      display_variants: [
        %DisplayVariant{
          id: "living-collage",
          label: "Living Collage",
          description: "Artwork is featured within a drifting collage of workshop moments."
        },
        %DisplayVariant{
          id: "quiet-spotlight",
          label: "Quiet Spotlight",
          description:
            "One artwork takes centre stage while workshop moments form a calm backdrop."
        }
      ],
      config_schema: %{
        "artwork_auto_publish" => %{type: :boolean, default: true},
        "moments_auto_publish" => %{type: :boolean, default: false},
        "display_variant" => %{
          type: :enum,
          default: "living-collage",
          values: ["living-collage", "quiet-spotlight"]
        }
      }
    }
  end

  @impl true
  def validate_config(config) when is_map(config), do: {:ok, config}
  def validate_config(_config), do: {:error, :invalid_config}
end
