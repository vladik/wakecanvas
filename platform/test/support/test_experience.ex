defmodule WakeCanvas.TestExperience do
  alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}

  def definition do
    definition = %Definition{
      id: "org.wakecanvas.test-display",
      name: "Test Display",
      version: "1.0.0",
      otp_application: :wake_canvas,
      surfaces: [
        %Surface{
          id: :display,
          path: "display",
          module: WakeCanvas.TestDisplayLive,
          role: :display
        }
      ],
      default_display_variant: "default",
      display_variants: [
        %DisplayVariant{
          id: "default",
          label: "Default",
          description: "Default test view",
          entrypoint: "static/default.js"
        },
        %DisplayVariant{
          id: "alternate",
          label: "Alternate",
          description: "Alternate test view",
          entrypoint: "static/alternate.js"
        },
        # Simulates a descriptor compiled before entrypoint/capability/fallback
        # fields were added to the SDK during a development code reload.
        %{id: "legacy", label: "Legacy", description: "Stale descriptor"}
      ]
    }

    # Simulates a Definition compiled before the stylesheet field was added.
    Map.delete(definition, :stylesheet)
  end

  def migrate_instance(instance) do
    File.mkdir_p!(instance.data_dir)
    File.write!(Path.join(instance.data_dir, "migration-ran"), instance.experience_version)
    :ok
  end
end

defmodule WakeCanvas.TestDisplayLive do
  use Phoenix.LiveView

  def mount(_params, session, socket),
    do: {:ok, assign(socket, :display_variant, session["display_variant"])}

  def render(assigns), do: ~H"<p>Variant: {@display_variant}</p>"
end
