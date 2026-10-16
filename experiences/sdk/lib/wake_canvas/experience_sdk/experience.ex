defmodule WakeCanvas.ExperienceSDK.Experience do
  @moduledoc "The required callback contract for a WakeCanvas Experience entry module."

  alias WakeCanvas.ExperienceSDK.Definition

  @callback definition() :: Definition.t()
  @callback validate_config(map()) :: {:ok, map()} | {:error, term()}
end
