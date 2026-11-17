defmodule WakeCanvas.Experience.CollectiveForm do
  @moduledoc """
  A participatory spatial Experience in which individual physical contributions
  become one evolving projected composition.

  Placement sources report observations through the same domain boundary. The
  initial release uses operator placement; a future camera adapter can report the
  same add, move, and remove observations without changing display variants.
  """

  @behaviour WakeCanvas.ExperienceSDK.Experience

  alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}

  @impl true
  def definition do
    %Definition{
      id: "org.wakecanvas.experience.collective-form",
      name: "Collective Form",
      version: "0.2.0",
      otp_application: :wake_canvas_experience_collective_form,
      stylesheet: "static/experience.css",
      surfaces: [
        %Surface{
          id: :display,
          path: "display",
          module: WakeCanvas.Experience.CollectiveForm.DisplayLive,
          role: :display,
          label: "Collective Form Table"
        },
        %Surface{
          id: :contribute,
          path: "contribute",
          module: WakeCanvas.Experience.CollectiveForm.ContributionLive,
          role: :primary_intake,
          label: "Add a Contribution"
        },
        %Surface{
          id: :table,
          path: "table",
          module: WakeCanvas.Experience.CollectiveForm.TableLive,
          role: :operator,
          label: "Table Console"
        }
      ],
      default_display_variant: "growing-mycelium",
      display_variants: [
        %DisplayVariant{
          id: "growing-mycelium",
          label: "Growing Mycelium",
          description:
            "A living network finds each contribution and weaves it into the collective organism.",
          entrypoint: "static/variants/growing-mycelium.js"
        },
        %DisplayVariant{
          id: "growing-mycelium-creature-reveals",
          label: "Growing Mycelium — Creature Reveals",
          description:
            "The living network periodically transforms into a creature, then dissolves back into the collective organism.",
          entrypoint: "static/variants/growing-mycelium-creature-reveals.js"
        }
      ],
      config_schema: %{
        "placement_source" => %{
          type: :enum,
          default: "operator",
          values: ["operator", "camera"]
        },
        "display_variant" => %{
          type: :enum,
          default: "growing-mycelium",
          values: ["growing-mycelium", "growing-mycelium-creature-reveals"]
        }
      }
    }
  end

  @impl true
  def validate_config(config) when is_map(config), do: {:ok, config}
  def validate_config(_config), do: {:error, :invalid_config}

  @impl true
  def migrate_instance(instance) do
    WakeCanvas.Experience.CollectiveForm.Store.migrate(instance.database_path)
  end

  @impl true
  def instance_child_spec(instance) do
    {WakeCanvas.Experience.CollectiveForm.InstanceRuntime, instance}
  end
end
