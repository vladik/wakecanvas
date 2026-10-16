defmodule WakeCanvas.ExperienceSDK.DisplayVariant do
  @moduledoc """
  A named visual presentation offered by an Experience display surface.

  Variant IDs are stable package-owned identifiers stored in instance configuration
  and accepted as temporary display URL overrides.
  """

  @enforce_keys [:id, :label, :description]
  defstruct [:id, :label, :description]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          description: String.t()
        }
end
