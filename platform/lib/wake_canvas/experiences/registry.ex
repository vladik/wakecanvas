defmodule WakeCanvas.Experiences.Registry do
  use GenServer

  alias WakeCanvas.ExperienceSDK.Definition

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def definition(experience_id), do: GenServer.call(__MODULE__, {:definition, experience_id})

  def surface(experience_id, path) do
    with {:ok, definition} <- definition(experience_id),
         surface when not is_nil(surface) <-
           Enum.find(definition.surfaces, &(&1.path == path)),
         true <- Code.ensure_loaded?(surface.module) do
      {:ok, surface}
    else
      nil -> {:error, :unknown_surface}
      false -> {:error, :surface_not_loaded}
      error -> error
    end
  end

  def display_variant(experience_id, requested_id \\ nil) do
    with {:ok, definition} <- definition(experience_id) do
      case definition.display_variants do
        [] ->
          {:ok, nil}

        variants ->
          id = requested_id || definition.default_display_variant

          case Enum.find(variants, &(&1.id == id)) do
            nil -> {:error, :unknown_display_variant}
            variant -> {:ok, variant}
          end
      end
    end
  end

  @impl true
  def init(:ok) do
    definitions =
      :wake_canvas
      |> Application.get_env(:development_experiences, [])
      |> Enum.reduce(%{}, &load_definition/2)

    {:ok, definitions}
  end

  @impl true
  def handle_call({:definition, experience_id}, _from, definitions) do
    case Map.fetch(definitions, experience_id) do
      {:ok, definition} -> {:reply, {:ok, definition}, definitions}
      :error -> {:reply, {:error, :experience_not_loaded}, definitions}
    end
  end

  defp load_definition(%{ebin: ebin, entry_module: entry_module}, definitions) do
    true = Code.append_path(String.to_charlist(ebin))
    module = Module.concat([entry_module])

    with true <- Code.ensure_loaded?(module),
         %Definition{} = definition <- module.definition() do
      Map.put(definitions, definition.id, definition)
    else
      _ -> definitions
    end
  end
end
