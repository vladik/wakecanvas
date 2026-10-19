defmodule WakeCanvas.Experience.LivingGallery.InstanceRuntime do
  @moduledoc false
  use GenServer

  def start_link(instance), do: GenServer.start_link(__MODULE__, instance)

  @impl true
  def init(instance) do
    File.mkdir_p!(Path.join(instance.data_dir, "media"))
    {:ok, instance}
  end
end
