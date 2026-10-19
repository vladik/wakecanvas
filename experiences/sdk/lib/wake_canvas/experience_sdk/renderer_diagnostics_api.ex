defmodule WakeCanvas.ExperienceSDK.RendererDiagnosticsAPI do
  @moduledoc """
  Optional platform service supplied to display LiveViews for browser diagnostics.

  Experience display code forwards the bounded payload emitted by the platform's
  `ExperienceRenderer` hook. Reporting is advisory: a renderer must continue to
  operate when the service is absent or a report is rejected.
  """

  @callback report(instance_id :: String.t(), payload :: map()) :: :ok
end
