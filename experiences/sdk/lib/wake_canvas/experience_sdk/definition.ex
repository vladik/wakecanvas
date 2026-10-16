defmodule WakeCanvas.ExperienceSDK.Definition do
  @moduledoc """
  Declarative, side-effect-free metadata returned by an Experience.

  Reading a definition must not start hardware or access an instance database.
  """

  @enforce_keys [:id, :name, :version, :otp_application, :surfaces]
  defstruct [
    :id,
    :name,
    :version,
    :otp_application,
    :surfaces,
    capabilities: [],
    config_schema: %{},
    display_variants: [],
    default_display_variant: nil
  ]

  alias WakeCanvas.ExperienceSDK.{DisplayVariant, Surface}

  @type capability ::
          :camera | :microphone | :touch | :participant_devices | :native_port | atom()

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          version: String.t(),
          otp_application: atom(),
          surfaces: [Surface.t()],
          capabilities: [capability()],
          config_schema: map(),
          display_variants: [DisplayVariant.t()],
          default_display_variant: String.t() | nil
        }
end
