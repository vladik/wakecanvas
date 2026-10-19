defmodule WakeCanvas.Experiences.ActiveInstanceSupervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link(options), do: DynamicSupervisor.start_link(__MODULE__, :ok, options)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
