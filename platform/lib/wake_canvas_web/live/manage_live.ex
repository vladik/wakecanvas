defmodule WakeCanvasWeb.ManageLive do
  use WakeCanvasWeb, :live_view

  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Instance
  alias WakeCanvas.Experiences.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:archive_candidate, nil) |> refresh()}
  end

  @impl true
  def handle_event("validate", %{"instance" => params}, socket) do
    form =
      %Instance{}
      |> Experiences.change_instance(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("create", %{"instance" => params}, socket) do
    case Experiences.create_instance(params) do
      {:ok, _instance} ->
        {:noreply, socket |> put_flash(:info, "Instance created") |> refresh()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("activate", %{"id" => id}, socket) do
    {:ok, _instance} = Experiences.activate_instance(id)
    {:noreply, socket |> put_flash(:info, "Instance is now active") |> refresh()}
  end

  def handle_event("stop", %{"id" => id}, socket) do
    {:ok, _instance} = Experiences.stop_instance(id)
    {:noreply, socket |> put_flash(:info, "Instance stopped") |> refresh()}
  end

  def handle_event("open_archive", %{"id" => id}, socket) do
    candidate = Enum.find(socket.assigns.instances, &(&1.id == String.to_integer(id)))
    {:noreply, assign(socket, :archive_candidate, candidate)}
  end

  def handle_event("cancel_archive", _params, socket),
    do: {:noreply, assign(socket, :archive_candidate, nil)}

  def handle_event("archive", %{"id" => id}, socket) do
    case Experiences.archive_instance(id) do
      {:ok, _instance} ->
        {:noreply,
         socket
         |> assign(:archive_candidate, nil)
         |> put_flash(
           :info,
           "Instance archived. Its content is still stored and can be restored."
         )
         |> refresh()}

      {:error, :active_instance} ->
        {:noreply, put_flash(socket, :error, "Stop the active instance before archiving it")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not archive instance: #{inspect(reason)}")}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case Experiences.restore_instance(id) do
      {:ok, _instance} ->
        {:noreply, socket |> put_flash(:info, "Instance restored") |> refresh()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not restore instance: #{inspect(reason)}")}
    end
  end

  defp refresh(socket) do
    packages = Experiences.list_packages()
    instances = Experiences.list_instances()
    active_variant = instances |> Enum.find(& &1.active) |> active_variant()

    socket
    |> assign(:page_title, "Manage WakeCanvas")
    |> assign(:packages, packages)
    |> assign(:instances, instances)
    |> assign(:active_variant, active_variant)
    |> assign(:archived_instances, Experiences.list_archived_instances())
    |> assign(:form, to_form(Experiences.change_instance(%Instance{})))
  end

  defp active_variant(nil), do: nil

  defp active_variant(instance) do
    configured = Map.get(instance.config, "display_variant")

    case Registry.display_variant(instance.experience_id, configured) do
      {:ok, variant} ->
        variant

      {:error, :unknown_display_variant} ->
        case Registry.display_variant(instance.experience_id) do
          {:ok, variant} -> variant
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-10">
        <section class="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="text-sm font-semibold uppercase tracking-[0.24em] text-primary">WakeCanvas</p>
            <h1 class="mt-2 text-4xl font-bold tracking-tight">Experience control room</h1>
            <p class="mt-3 max-w-2xl text-base-content/65">
              Choose what this kiosk is running. Each instance keeps its own workshop configuration and content.
            </p>
          </div>
          <.link href={~p"/display"} class="btn btn-primary btn-lg">
            <span :if={@active_variant}>Open active display · {@active_variant.label}</span>
            <span :if={!@active_variant}>Open active display</span>
          </.link>
        </section>

        <section>
          <h2 class="mb-4 text-xl font-semibold">Installed Experiences</h2>
          <div class="grid gap-4 md:grid-cols-2">
            <div :for={package <- @packages} class="card border border-base-300 bg-base-100 shadow-sm">
              <div class="card-body">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <h3 class="card-title">{package.name}</h3>
                    <p class="font-mono text-xs text-base-content/50">{package.id}</p>
                  </div>
                  <span class="badge badge-success badge-outline">v{package.version}</span>
                </div>
                <p class="mt-3 text-sm text-base-content/70">
                  Ambient workshop moments and participant artwork become one living projected gallery.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section>
          <div class="mb-4 flex items-center justify-between">
            <h2 class="text-xl font-semibold">Instances</h2>
            <span class="badge badge-neutral">{length(@instances)} configured</span>
          </div>

          <div class="grid gap-4 lg:grid-cols-2">
            <article
              :for={instance <- @instances}
              class={[
                "card border bg-base-100 shadow-sm",
                instance.active && "border-primary ring-2 ring-primary/20",
                !instance.active && "border-base-300"
              ]}
            >
              <div class="card-body">
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-widest text-base-content/45">
                      Instance #{instance.id}
                    </p>
                    <h3 class="card-title mt-1">{instance.name}</h3>
                    <p class="text-sm text-base-content/60">{instance.package.name}</p>
                  </div>
                  <span :if={instance.active} class="badge badge-primary gap-2">
                    <span class="size-2 animate-pulse rounded-full bg-primary-content"></span> Active
                  </span>
                  <span :if={!instance.active} class="badge badge-ghost">Stopped</span>
                </div>

                <div class="card-actions mt-5 justify-end">
                  <.link href={~p"/i/#{instance.id}/artwork"} class="btn btn-ghost btn-sm">Artwork intake</.link>
                  <.link href={~p"/i/#{instance.id}/moments"} class="btn btn-ghost btn-sm">Moments</.link>
                  <.link href={~p"/i/#{instance.id}/review"} class="btn btn-ghost btn-sm">Review</.link>
                  <.link href={~p"/i/#{instance.id}/settings"} class="btn btn-ghost btn-sm">Settings</.link>
                  <.link href={~p"/i/#{instance.id}/display"} class="btn btn-ghost btn-sm">
                    Preview
                  </.link>
                  <button
                    :if={!instance.active}
                    phx-click="open_archive"
                    phx-value-id={instance.id}
                    class="btn btn-ghost btn-sm text-error"
                  >
                    Archive
                  </button>
                  <button
                    :if={!instance.active}
                    phx-click="activate"
                    phx-value-id={instance.id}
                    class="btn btn-primary btn-sm"
                  >
                    Start
                  </button>
                  <button
                    :if={instance.active}
                    phx-click="stop"
                    phx-value-id={instance.id}
                    class="btn btn-outline btn-sm"
                  >
                    Stop
                  </button>
                </div>
              </div>
            </article>
          </div>
        </section>

        <section :if={@archived_instances != []} class="card border border-base-300 bg-base-200/40">
          <div class="card-body">
            <h2 class="card-title">Archived instances</h2>
            <p class="text-sm text-base-content/60">
              Archived workshops and all their images remain on this kiosk.
            </p>
            <div class="mt-2 divide-y divide-base-300">
              <div
                :for={instance <- @archived_instances}
                class="flex items-center justify-between gap-4 py-3"
              >
                <div>
                  <p class="font-semibold">{instance.name}</p>
                  <p class="text-xs text-base-content/55">
                    Instance #{instance.id} · {instance.package.name}
                  </p>
                </div>
                <button phx-click="restore" phx-value-id={instance.id} class="btn btn-outline btn-sm">Restore</button>
              </div>
            </div>
          </div>
        </section>

        <section class="card border border-base-300 bg-base-200/40">
          <div class="card-body">
            <h2 class="card-title">Create a workshop instance</h2>
            <.form
              for={@form}
              phx-change="validate"
              phx-submit="create"
              class="mt-3 grid gap-4 md:grid-cols-[1fr_1fr_auto] md:items-end"
            >
              <.input
                field={@form[:name]}
                label="Instance name"
                placeholder="Saturday afternoon workshop"
              />
              <.input
                field={@form[:experience_id]}
                type="select"
                label="Experience"
                prompt="Choose an Experience"
                options={Enum.map(@packages, &{&1.name, &1.id})}
              />
              <button class="btn btn-primary">Create instance</button>
            </.form>
          </div>
        </section>
      </div>

      <dialog :if={@archive_candidate} open class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Archive {@archive_candidate.name}?</h3>
          <p class="py-4 text-base-content/70">
            It will disappear from the active instance list, but its database and uploaded images will remain safely stored. You can restore it later.
          </p>
          <div class="modal-action">
            <button phx-click="cancel_archive" class="btn">Cancel</button>
            <button phx-click="archive" phx-value-id={@archive_candidate.id} class="btn btn-warning">Archive instance</button>
          </div>
        </div>
        <button phx-click="cancel_archive" class="modal-backdrop" aria-label="Cancel archive">close</button>
      </dialog>
    </Layouts.app>
    """
  end
end
