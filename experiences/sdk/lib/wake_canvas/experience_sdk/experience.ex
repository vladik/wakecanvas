defmodule WakeCanvas.ExperienceSDK.Experience do
  @moduledoc "The required callback contract for a WakeCanvas Experience entry module."

  alias WakeCanvas.ExperienceSDK.{Definition, Instance}

  @callback definition() :: Definition.t()
  @callback validate_config(map()) :: {:ok, map()} | {:error, term()}
  @callback migrate_instance(Instance.t()) :: :ok | {:error, term()}
  @callback instance_child_spec(Instance.t()) :: Supervisor.child_spec()

  @optional_callbacks migrate_instance: 1, instance_child_spec: 1
end
