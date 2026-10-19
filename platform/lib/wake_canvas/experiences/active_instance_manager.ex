defmodule WakeCanvas.Experiences.ActiveInstanceManager do
  @moduledoc false
  use GenServer

  require Logger

  alias WakeCanvas.ExperienceSDK.Instance, as: SDKInstance
  alias WakeCanvas.Experiences.{GenericInstanceRuntime, InstancePaths, Registry}

  @supervisor WakeCanvas.Experiences.ActiveInstanceSupervisor

  def start_link(options),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(options, :name, __MODULE__))

  def switch(instance), do: GenServer.call(__MODULE__, {:switch, instance}, 15_000)
  def stop(instance_id), do: GenServer.call(__MODULE__, {:stop, instance_id}, 15_000)
  def status, do: GenServer.call(__MODULE__, :status)

  @impl true
  def init(:ok) do
    if Application.get_env(:wake_canvas, :restore_active_instance, true) do
      send(self(), :restore_selected_instance)
    end

    {:ok, empty_state()}
  end

  @impl true
  def handle_call({:switch, instance}, _from, state) do
    if state.instance_id == instance.id and process_alive?(state.pid) do
      {:reply, :ok, state}
    else
      previous = state
      stop_runtime(state)

      case start_runtime(instance) do
        {:ok, next} ->
          {:reply, :ok, next}

        {:error, reason} ->
          restored = restore_previous(previous)
          {:reply, {:error, {:start_failed, reason}}, %{restored | last_error: reason}}
      end
    end
  end

  def handle_call({:stop, instance_id}, _from, %{instance_id: instance_id} = state) do
    {:reply, :ok, stop_runtime(state)}
  end

  def handle_call({:stop, _instance_id}, _from, state), do: {:reply, :ok, state}

  def handle_call(:status, _from, state) do
    status = %{
      instance_id: state.instance_id,
      running: process_alive?(state.pid),
      last_error: state.last_error
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:restore_selected_instance, state) do
    case WakeCanvas.Experiences.active_instance() do
      nil ->
        {:noreply, state}

      instance ->
        case start_runtime(instance) do
          {:ok, restored} ->
            {:noreply, restored}

          {:error, reason} ->
            Logger.error(
              "Could not restore active Experience instance #{instance.id}: #{inspect(reason)}"
            )

            {:noreply, %{state | instance_id: instance.id, last_error: reason}}
        end
    end
  rescue
    error ->
      Logger.error("Could not read the selected Experience instance: #{Exception.message(error)}")
      {:noreply, %{state | last_error: error}}
  end

  def handle_info({:DOWN, monitor, :process, pid, reason}, %{monitor: monitor, pid: pid} = state) do
    error = if reason in [:normal, :shutdown], do: nil, else: reason
    {:noreply, %{state | pid: nil, monitor: nil, last_error: error}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_runtime(instance) do
    InstancePaths.ensure!(instance.id)
    context = instance_context(instance)

    with {:ok, module} <- Registry.entry_module(instance.experience_id),
         :ok <- migrate_instance(module, context),
         child_spec <- child_spec(module, context),
         {:ok, pid} <- DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok,
       %{
         instance_id: instance.id,
         instance: instance,
         pid: pid,
         monitor: Process.monitor(pid),
         last_error: nil
       }}
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp migrate_instance(module, context) do
    if function_exported?(module, :migrate_instance, 1) do
      case module.migrate_instance(context) do
        :ok -> :ok
        {:error, reason} -> {:error, {:migration_failed, reason}}
        other -> {:error, {:invalid_migration_result, other}}
      end
    else
      :ok
    end
  rescue
    error -> {:error, {:migration_exception, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:migration_failure, kind, reason}}
  end

  defp child_spec(module, context) do
    spec =
      if function_exported?(module, :instance_child_spec, 1) do
        module.instance_child_spec(context)
      else
        {GenericInstanceRuntime, context}
      end

    spec
    |> Supervisor.child_spec([])
    |> Map.put(:id, {:wakecanvas_experience_instance, context.id})
    |> Map.put(:restart, :temporary)
  end

  defp instance_context(instance) do
    %SDKInstance{
      id: instance.id,
      experience_id: instance.experience_id,
      experience_version: instance.package.version,
      name: instance.name,
      config: instance.config,
      data_dir: InstancePaths.data_dir(instance.id),
      database_path: InstancePaths.database_path(instance.id)
    }
  end

  defp stop_runtime(%{pid: pid, monitor: monitor} = state) when is_pid(pid) do
    if monitor, do: Process.demonitor(monitor, [:flush])

    if process_alive?(pid) do
      DynamicSupervisor.terminate_child(@supervisor, pid)
    end

    empty_state()
    |> Map.put(:last_error, state.last_error)
  end

  defp stop_runtime(state), do: %{empty_state() | last_error: state.last_error}

  defp restore_previous(%{instance: nil}), do: empty_state()

  defp restore_previous(%{instance: instance}) do
    case start_runtime(instance) do
      {:ok, restored} -> restored
      {:error, reason} -> %{empty_state() | last_error: {:restore_failed, reason}}
    end
  end

  defp process_alive?(pid) when is_pid(pid), do: Process.alive?(pid)
  defp process_alive?(_pid), do: false

  defp empty_state,
    do: %{instance_id: nil, instance: nil, pid: nil, monitor: nil, last_error: nil}
end
