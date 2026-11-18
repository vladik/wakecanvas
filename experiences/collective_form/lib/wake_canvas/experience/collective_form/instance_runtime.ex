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
    maintain(instance)
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

  defp maintain(instance) do
    result = Store.maintain(instance.database_path)

    if result.retired_deleted > 0 or result.completed_cycles_deleted > 0 do
      Logger.info(
        "Collective Form startup maintenance for instance #{instance.id} removed #{result.retired_deleted} retired connections and #{result.completed_cycles_deleted} completed cycles"
      )
    end
  rescue
    error ->
      Logger.warning(
        "Collective Form startup maintenance failed for instance #{instance.id}: #{Exception.message(error)}"
      )
  end

  defp schedule_evolution(delay), do: Process.send_after(self(), :evolve, delay)
end
