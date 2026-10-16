defmodule WakeCanvas.Experiences.ConfigAPI do
  @moduledoc false
  @behaviour WakeCanvas.ExperienceSDK.ConfigAPI

  alias WakeCanvas.Experiences

  @impl true
  def update_instance_config(instance_id, patch) do
    with instance when not is_nil(instance) <- Experiences.get_instance(instance_id),
         {:ok, updated} <- Experiences.update_instance_config(instance, patch) do
      {:ok, updated.config}
    else
      nil -> {:error, :instance_not_found}
      error -> error
    end
  end
end
