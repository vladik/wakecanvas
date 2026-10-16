defmodule WakeCanvas.TestExperience do
  alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}

  def definition do
    %Definition{
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
        %DisplayVariant{id: "default", label: "Default", description: "Default test view"},
        %DisplayVariant{id: "alternate", label: "Alternate", description: "Alternate test view"}
      ]
    }
  end
end

defmodule WakeCanvas.TestDisplayLive do
  use Phoenix.LiveView

  def mount(_params, session, socket),
    do: {:ok, assign(socket, :display_variant, session["display_variant"])}

  def render(assigns), do: ~H"<p>Variant: {@display_variant}</p>"
end
