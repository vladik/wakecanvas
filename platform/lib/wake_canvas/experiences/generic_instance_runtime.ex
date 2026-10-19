defmodule WakeCanvas.Experiences.GenericInstanceRuntime do
  @moduledoc false
  use GenServer

  def start_link(instance), do: GenServer.start_link(__MODULE__, instance)

  @impl true
  def init(instance), do: {:ok, instance}
end
