defmodule WakeCanvas.ExperienceSDK.ConfigAPI do
  @moduledoc """
  Platform service exposed to trusted Experience operator surfaces.

  Experiences use the module supplied in their surface session rather than taking
  a compile-time dependency on the WakeCanvas platform.
  """

  @callback update_instance_config(pos_integer(), map()) ::
              {:ok, map()} | {:error, term()}
end
