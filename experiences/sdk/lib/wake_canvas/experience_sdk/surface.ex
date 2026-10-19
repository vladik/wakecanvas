defmodule WakeCanvas.ExperienceSDK.Surface do
  @moduledoc """
  A browser surface contributed by an Experience behind a platform-owned route.

  `path` is one relative URL segment below `/i/:instance_uuid/`. The platform keeps
  control of the endpoint and resolves the module through the active package.
  """

  @enforce_keys [:id, :path, :module, :role]
  defstruct [:id, :path, :module, :role, :label]

  @type role :: :display | :primary_intake | :participant | :operator

  @type t :: %__MODULE__{
          id: atom(),
          path: String.t(),
          module: module(),
          role: role(),
          label: String.t() | nil
        }
end
