defmodule WakeCanvas.ExperienceSDK.DisplayVariant do
  @moduledoc """
  A named visual presentation offered by an Experience display surface.

  Variant IDs are stable package-owned identifiers stored in instance configuration
  and accepted as explicit display URL overrides. `entrypoint` is a browser-ready
  ES module path inside the Experience's `priv` directory.
  """

  @enforce_keys [:id, :label, :description, :entrypoint]
  defstruct [:id, :label, :description, :entrypoint, :thumbnail, capabilities: [], fallback: nil]

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          description: String.t(),
          entrypoint: String.t(),
          thumbnail: String.t() | nil,
          capabilities: [atom()],
          fallback: String.t() | nil
        }
end
