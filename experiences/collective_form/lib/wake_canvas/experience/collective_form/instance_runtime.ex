defmodule WakeCanvas.Experience.CollectiveForm.InstanceRuntime do
  @moduledoc false
  use GenServer

  require Logger

  alias WakeCanvas.Experience.CollectiveForm.Store

  @evolution_interval 4_000

  def start_link(instance), do: GenServer.start_link(__MODULE__, instance)

  @impl true
  def init(instance) do
    File.mkdir_p!(Path.join(instance.data_dir, "media"))
    schedule_evolution(250)
    {:ok, instance}
  end

  @impl true
  def handle_info(:evolve, instance) do
    evolve(instance)
    schedule_evolution(@evolution_interval)
    {:noreply, instance}
  end

  defp evolve(instance) do
    Store.evolve(instance.database_path)
  rescue
    error ->
      Logger.warning(
        "Collective Form route evolution failed for instance #{instance.id}: #{Exception.message(error)}"
      )
  end

  defp schedule_evolution(delay), do: Process.send_after(self(), :evolve, delay)
end
