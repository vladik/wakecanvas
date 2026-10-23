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
      version: "0.2.0",
      otp_application: :wake_canvas_experience_living_gallery,
      stylesheet: "static/experience.css",
      surfaces: [
        %Surface{
          id: :display,
          path: "display",
          module: WakeCanvas.Experience.LivingGallery.RendererDisplayLive,
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
          id: :messages,
          path: "messages",
          module: WakeCanvas.Experience.LivingGallery.MessageIntakeLive,
          role: :participant,
          label: "Share a Message"
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
      capabilities: [:camera, :microphone, :participant_devices],
      default_display_variant: "living-collage",
      display_variants: [
        %DisplayVariant{
          id: "living-collage",
          label: "Living Film Collage",
          description:
            "Workshop memories flow through film ribbons while colourful artwork animates the foreground.",
          entrypoint: "static/variants/drifting-collage.js",
          thumbnail: "static/previews/living-collage.svg",
          capabilities: [:webgl],
          fallback: "community-tapestry"
        },
        %DisplayVariant{
          id: "quiet-spotlight",
          label: "Living Light",
          description:
            "Artwork is revealed through prismatic light while workshop memories dissolve behind it.",
          entrypoint: "static/variants/quiet-spotlight.js",
          thumbnail: "static/previews/quiet-spotlight.svg"
        },
        %DisplayVariant{
          id: "gallery-orbit",
          label: "Living Spiral",
          description:
            "Artwork comes into the light while workshop memories travel through a cinematic spiral.",
          entrypoint: "static/variants/gallery-orbit.js",
          thumbnail: "static/previews/gallery-orbit.svg",
          capabilities: [:webgl2],
          fallback: "community-tapestry"
        },
        %DisplayVariant{
          id: "gallery-orbit-focus",
          label: "Living Spiral — Focus",
          description:
            "A clean, frameless spiral with artwork enlarged for a full-screen spotlight.",
          entrypoint: "static/variants/gallery-orbit-focus.js",
          thumbnail: "static/previews/gallery-orbit-focus.svg",
          capabilities: [:webgl2],
          fallback: "community-tapestry"
        },
        %DisplayVariant{
          id: "growing-canvas",
          label: "Growing Canvas",
          description: "Each contribution becomes a seed in a generative garden.",
          entrypoint: "static/variants/growing-canvas.js",
          thumbnail: "static/previews/growing-canvas.svg",
          capabilities: [:webgl],
          fallback: "community-tapestry"
        },
        %DisplayVariant{
          id: "community-tapestry",
          label: "Community Tapestry",
          description:
            "Artwork, memories, and messages are stitched into an accessible community composition.",
          entrypoint: "static/variants/community-tapestry.js",
          thumbnail: "static/previews/community-tapestry.svg"
        },
        %DisplayVariant{
          id: "gravity-playground",
          label: "Living Balance",
          description:
            "An endless artwork rain changes suspended memory platforms and takes turns in a central spotlight.",
          entrypoint: "static/variants/gravity-playground.js",
          thumbnail: "static/previews/gravity-playground.svg",
          capabilities: [:webgl],
          fallback: "community-tapestry"
        }
      ],
      config_schema: %{
        "artwork_auto_publish" => %{type: :boolean, default: true},
        "moments_auto_publish" => %{type: :boolean, default: false},
        "messages_auto_publish" => %{type: :boolean, default: false},
        "retain_originals" => %{type: :boolean, default: true},
        "presentation_label" => %{type: :string, default: "Living Gallery"},
        "presentation_title" => %{type: :string, default: ""},
        "presentation_description" => %{type: :string, default: ""},
        "display_variant" => %{
          type: :enum,
          default: "living-collage",
          values: [
            "living-collage",
            "quiet-spotlight",
            "gallery-orbit",
            "gallery-orbit-focus",
            "growing-canvas",
            "community-tapestry",
            "gravity-playground"
          ]
        }
      }
    }
  end

  @impl true
  def validate_config(config) when is_map(config), do: {:ok, config}
  def validate_config(_config), do: {:error, :invalid_config}

  @impl true
  def migrate_instance(instance) do
    WakeCanvas.Experience.LivingGallery.Store.migrate(instance.database_path)
  end

  @impl true
  def instance_child_spec(instance) do
    {WakeCanvas.Experience.LivingGallery.InstanceRuntime, instance}
  end
end
