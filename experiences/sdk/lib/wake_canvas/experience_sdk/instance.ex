defmodule WakeCanvas.ExperienceSDK.Instance do
  @moduledoc """
  Runtime context for one configured instance of an Experience.

  The platform creates this value when activating an instance. An Experience owns
  the contents of `config` and all persistent data below `data_dir`; it must not
  access another instance's paths or store persistent data elsewhere. The platform
  treats `data_dir` as the complete instance deletion boundary.
  """

  @enforce_keys [
    :id,
    :experience_id,
    :experience_version,
    :name,
    :config,
    :data_dir,
    :database_path
  ]
  defstruct [:id, :experience_id, :experience_version, :name, :config, :data_dir, :database_path]

  @type t :: %__MODULE__{
          id: pos_integer(),
          experience_id: String.t(),
          experience_version: String.t(),
          name: String.t(),
          config: map(),
          data_dir: String.t(),
          database_path: String.t()
        }
end
