defmodule WakeCanvas.Diagnostics.RendererMonitor do
  @moduledoc false

  use GenServer

  @behaviour WakeCanvas.ExperienceSDK.RendererDiagnosticsAPI

  @stale_after_ms 45_000
  @max_clients 200
  @allowed_statuses ~w(running error context_lost context_restored stopped)

  def start_link(options),
    do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(options, :name, __MODULE__))

  @impl true
  def report(instance_id, payload) when is_binary(instance_id) and is_map(payload) do
    GenServer.cast(__MODULE__, {:report, instance_id, payload})
  catch
    :exit, _ -> :ok
  end

  def report(_instance_id, _payload), do: :ok

  def snapshot(instance_id \\ nil), do: GenServer.call(__MODULE__, {:snapshot, instance_id})
  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:report, instance_id, payload}, state) do
    now = System.monotonic_time(:millisecond)
    state = prune(state, now)

    case normalize(instance_id, payload, now) do
      {:ok, %{status: "stopped", client_id: client_id}} ->
        {:noreply, Map.delete(state, {instance_id, client_id})}

      {:ok, report} ->
        state = state |> Map.put({instance_id, report.client_id}, report) |> limit_clients()
        {:noreply, state}

      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:snapshot, instance_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    state = prune(state, now)

    reports =
      state
      |> Map.values()
      |> Enum.filter(&(is_nil(instance_id) or &1.instance_id == instance_id))
      |> Enum.sort_by(& &1.received_monotonic_ms, :desc)

    {:reply, reports, state}
  end

  def handle_call(:clear, _from, _state), do: {:reply, :ok, %{}}

  defp normalize(instance_id, payload, now) do
    with {:ok, client_id} <- bounded_string(payload["clientId"], 64),
         {:ok, status} <- enum_string(payload["status"], @allowed_statuses),
         {:ok, requested_variant} <- optional_string(payload["requestedVariant"], 80),
         {:ok, active_variant} <- optional_string(payload["activeVariant"], 80),
         {:ok, fallback_reason} <- optional_string(payload["fallbackReason"], 240),
         {:ok, error_message} <- optional_string(payload["error"], 400),
         {:ok, width} <- bounded_integer(payload["width"], 0, 16_384),
         {:ok, height} <- bounded_integer(payload["height"], 0, 16_384),
         {:ok, dpr} <- bounded_number(payload["devicePixelRatio"], 0.25, 8.0),
         {:ok, fps} <- optional_number(payload["fps"], 0.0, 240.0),
         {:ok, visible} <- boolean(payload["visible"]),
         {:ok, fallback} <- boolean(payload["fallback"]),
         {:ok, webgl2} <- boolean(payload["webgl2"]) do
      {:ok,
       %{
         instance_id: instance_id,
         client_id: client_id,
         status: status,
         requested_variant: requested_variant,
         active_variant: active_variant,
         fallback: fallback,
         fallback_reason: fallback_reason,
         error: error_message,
         width: width,
         height: height,
         device_pixel_ratio: dpr,
         fps: fps,
         visible: visible,
         webgl2: webgl2,
         received_at: DateTime.utc_now() |> DateTime.truncate(:second),
         received_monotonic_ms: now
       }}
    else
      _ -> :error
    end
  end

  defp bounded_string(value, max)
       when is_binary(value) and byte_size(value) >= 1 and byte_size(value) <= max,
       do: {:ok, value}

  defp bounded_string(_, _), do: :error
  defp optional_string(nil, _max), do: {:ok, nil}
  defp optional_string(value, max), do: bounded_string(value, max)

  defp enum_string(value, allowed) do
    if value in allowed, do: {:ok, value}, else: :error
  end

  defp bounded_integer(value, min, max) when is_integer(value) and value >= min and value <= max,
    do: {:ok, value}

  defp bounded_integer(_, _, _), do: :error

  defp bounded_number(value, min, max) when is_number(value) and value >= min and value <= max,
    do: {:ok, value / 1}

  defp bounded_number(_, _, _), do: :error
  defp optional_number(nil, _min, _max), do: {:ok, nil}
  defp optional_number(value, min, max), do: bounded_number(value, min, max)
  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean(_), do: :error

  defp prune(state, now) do
    Map.reject(state, fn {_key, report} ->
      now - report.received_monotonic_ms > @stale_after_ms
    end)
  end

  defp limit_clients(state) when map_size(state) <= @max_clients, do: state

  defp limit_clients(state) do
    {oldest_key, _report} =
      Enum.min_by(state, fn {_key, report} -> report.received_monotonic_ms end)

    Map.delete(state, oldest_key)
  end
end
