defmodule WakeCanvasWeb.ManageLive do
  use WakeCanvasWeb, :live_view

  alias WakeCanvas.Diagnostics
  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.ActiveInstanceManager
  alias WakeCanvas.Experiences.Instance
  alias WakeCanvas.Experiences.Registry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_upload(:experience_package,
       accept: [".wakecanvas"],
       max_entries: 1,
       max_file_size: 128 * 1024 * 1024
     )
     |> allow_upload(:instance_archive,
       accept: [".wakecanvas-instance"],
       max_entries: 1,
       max_file_size: 2 * 1024 * 1024 * 1024
     )
     |> assign(:instance_import_mode, "preserve")
     |> assign(:instance_import_confirmation, "")
     |> assign(:rollback_candidate, nil)
     |> assign(:uninstall_candidate, nil)
     |> assign(:uninstall_confirmation, "")
     |> assign(:archive_candidate, nil)
     |> assign(:purge_candidate, nil)
     |> assign(:purge_confirmation, "")
     |> assign(:diagnostics, Diagnostics.snapshot())
     |> refresh()}
  end

  def handle_event("refresh_diagnostics", _params, socket) do
    {:noreply, assign(socket, :diagnostics, Diagnostics.snapshot())}
  end

  def handle_event("open_package_rollback", %{"id" => id}, socket) do
    {:noreply, assign(socket, :rollback_candidate, find_package(socket, id))}
  end

  def handle_event("cancel_package_rollback", _params, socket),
    do: {:noreply, assign(socket, :rollback_candidate, nil)}

  def handle_event("rollback_package", %{"id" => id}, socket) do
    case Experiences.rollback_package(id) do
      {:ok, package} ->
        {:noreply,
         socket
         |> assign(:rollback_candidate, nil)
         |> put_flash(
           :info,
           "#{package.name} #{package.version} is staged. Restart WakeCanvas to complete rollback."
         )
         |> refresh()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, package_error(reason))}
    end
  end

  def handle_event("open_package_uninstall", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:uninstall_candidate, find_package(socket, id))
     |> assign(:uninstall_confirmation, "")}
  end

  def handle_event("cancel_package_uninstall", _params, socket),
    do:
      {:noreply,
       socket |> assign(:uninstall_candidate, nil) |> assign(:uninstall_confirmation, "")}

  def handle_event("validate_package_uninstall", %{"confirmation" => confirmation}, socket),
    do: {:noreply, assign(socket, :uninstall_confirmation, confirmation)}

  def handle_event(
        "uninstall_package",
        %{"package_id" => id, "confirmation" => confirmation},
        socket
      ) do
    case Experiences.uninstall_package(id, confirmation) do
      {:ok, package} ->
        {:noreply,
         socket
         |> assign(:uninstall_candidate, nil)
         |> assign(:uninstall_confirmation, "")
         |> put_flash(:info, "#{package.name} was uninstalled.")
         |> refresh()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, package_error(reason))}
    end
  end

  def handle_event("validate_package", _params, socket), do: {:noreply, socket}

  def handle_event("install_package", _params, socket) do
    results =
      consume_uploaded_entries(socket, :experience_package, fn %{path: path}, _entry ->
        {:ok, Experiences.stage_package_install(path)}
      end)

    case results do
      [{:ok, {:ok, package}}] ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{package.name} #{package.version} was validated and staged. Restart WakeCanvas to activate it."
         )
         |> refresh()}

      [{:ok, {:error, reason}}] ->
        {:noreply, put_flash(socket, :error, package_error(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a .wakecanvas package first.")}
    end
  end

  def handle_event("validate_instance_import", params, socket) do
    {:noreply,
     socket
     |> assign(:instance_import_mode, Map.get(params, "mode", "preserve"))
     |> assign(:instance_import_confirmation, Map.get(params, "confirmation", ""))}
  end

  def handle_event("import_instance", params, socket) do
    mode = Map.get(params, "mode", "preserve")
    confirmation = Map.get(params, "confirmation", "")

    results =
      consume_uploaded_entries(socket, :instance_archive, fn %{path: path}, _entry ->
        {:ok, Experiences.import_instance(path, import_mode(mode), confirmation)}
      end)

    case results do
      [{:ok, {:ok, instance}}] ->
        {:noreply,
         socket
         |> assign(:instance_import_confirmation, "")
         |> put_flash(
           :info,
           "#{instance.name} was imported as an archived instance. Review it, then restore it when ready."
         )
         |> refresh()}

      [{:ok, {:error, reason}}] ->
        {:noreply, put_flash(socket, :error, instance_archive_error(reason))}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a .wakecanvas-instance archive first.")}
    end
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
    case Experiences.activate_instance(id) do
      {:ok, _instance} ->
        {:noreply, socket |> put_flash(:info, "Instance is now active") |> refresh()}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not start the Experience: #{inspect(reason)}")}
    end
  end

  def handle_event("stop", %{"id" => id}, socket) do
    case Experiences.stop_instance(id) do
      {:ok, _instance} ->
        {:noreply, socket |> put_flash(:info, "Instance stopped") |> refresh()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not stop the Experience: #{inspect(reason)}")}
    end
  end

  def handle_event("open_archive", %{"id" => id}, socket) do
    candidate = Enum.find(socket.assigns.instances, &(&1.id == id))
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

  def handle_event("open_purge", %{"id" => id}, socket) do
    candidate = Enum.find(socket.assigns.archived_instances, &(&1.id == id))

    {:noreply, socket |> assign(:purge_candidate, candidate) |> assign(:purge_confirmation, "")}
  end

  def handle_event("validate_purge", %{"confirmation" => confirmation}, socket),
    do: {:noreply, assign(socket, :purge_confirmation, confirmation)}

  def handle_event("cancel_purge", _params, socket),
    do: {:noreply, socket |> assign(:purge_candidate, nil) |> assign(:purge_confirmation, "")}

  def handle_event(
        "purge",
        %{"instance_id" => id, "confirmation" => confirmation},
        socket
      ) do
    case Experiences.purge_instance(id, confirmation) do
      {:ok, _instance} ->
        {:noreply,
         socket
         |> assign(:purge_candidate, nil)
         |> assign(:purge_confirmation, "")
         |> put_flash(:info, "Instance and all of its stored content were permanently deleted.")
         |> refresh()}

      {:error, :confirmation_mismatch} ->
        {:noreply, put_flash(socket, :error, "Type the exact instance name to confirm.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not purge instance: #{inspect(reason)}")}
    end
  end

  def handle_event(
        "set_participant_code",
        %{"instance_id" => id, "code" => code},
        socket
      ) do
    case Experiences.set_participant_code(id, code) do
      {:ok, instance} ->
        message =
          if instance.participant_code_digest,
            do: "Participant code updated. Existing participant sessions were signed out.",
            else: "Participant uploads are now open without a code."

        {:noreply, socket |> put_flash(:info, message) |> refresh()}

      {:error, :invalid_code} ->
        {:noreply,
         put_flash(socket, :error, "Use exactly six digits, or leave it empty to open access.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not update participant code: #{inspect(reason)}")}
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
    |> assign(:runtime_status, ActiveInstanceManager.status())
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

        <section class="alert border border-base-300 bg-base-100">
          <div>
            <p class="font-semibold">Runtime</p>
            <p class="text-sm text-base-content/65">
              <span :if={@runtime_status.running}>Active Experience process is healthy.</span>
              <span :if={!@runtime_status.running && !@runtime_status.last_error}>No Experience process is running.</span>
              <span :if={@runtime_status.last_error}>Last start/runtime error: {inspect(
                @runtime_status.last_error
              )}</span>
            </p>
          </div>
        </section>

        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
              <div>
                <div class="flex items-center gap-2">
                  <h2 class="card-title">Kiosk health</h2>
                  <span class={diagnostic_badge_class(@diagnostics.status)}>
                    {@diagnostics.status |> Atom.to_string() |> String.upcase()}
                  </span>
                </div>
                <p class="mt-1 text-sm text-base-content/60">
                  Platform {@diagnostics.platform_version} · uptime {format_duration(
                    @diagnostics.uptime_seconds
                  )} · checked {Calendar.strftime(@diagnostics.generated_at, "%H:%M:%S UTC")}
                </p>
              </div>
              <button phx-click="refresh_diagnostics" class="btn btn-outline btn-sm">
                Refresh diagnostics
              </button>
            </div>

            <div class="mt-3 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <div
                :for={check <- @diagnostics.checks}
                class="rounded-box border border-base-300 bg-base-200/40 p-4"
              >
                <div class="flex items-center justify-between gap-3">
                  <p class="font-semibold">{check.label}</p>
                  <span class={diagnostic_badge_class(check.status)}>{check.status}</span>
                </div>
                <p class="mt-2 text-sm text-base-content/65">{check.message}</p>
              </div>
            </div>
            <p class="mt-3 text-xs text-base-content/45">
              Machine-readable status is available at <code>/health</code>. It excludes access codes and filesystem paths.
            </p>
          </div>
        </section>

        <section>
          <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 class="text-xl font-semibold">Experience packages</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Install a validated package built by an Experience developer. Activation happens after restart.
              </p>
            </div>
            <form
              phx-change="validate_package"
              phx-submit="install_package"
              class="flex items-end gap-2"
            >
              <label class="form-control">
                <span class="label-text text-xs font-semibold">.wakecanvas package</span>
                <.live_file_input
                  upload={@uploads.experience_package}
                  class="file-input file-input-bordered file-input-sm max-w-xs"
                />
              </label>
              <button
                class="btn btn-primary btn-sm"
                disabled={@uploads.experience_package.entries == []}
              >
                Validate and stage
              </button>
            </form>
          </div>
          <div class="grid gap-4 md:grid-cols-2">
            <div :for={package <- @packages} class="card border border-base-300 bg-base-100 shadow-sm">
              <div class="card-body">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <h3 class="card-title">{package.name}</h3>
                    <p class="font-mono text-xs text-base-content/50">{package.id}</p>
                  </div>
                  <div class="flex flex-col items-end gap-1">
                    <span class="badge badge-success badge-outline">v{package.version}</span>
                    <span
                      :if={package.status == "pending_restart"}
                      class="badge badge-warning badge-sm"
                    >
                      Restart required
                    </span>
                    <span :if={package.status == "installed"} class="badge badge-ghost badge-sm">
                      Installed
                    </span>
                    <span :if={package.status == "rejected"} class="badge badge-error badge-sm">
                      Rejected
                    </span>
                  </div>
                </div>
                <p class="mt-3 text-sm text-base-content/70">
                  Independently packaged Experience code and browser assets for this kiosk.
                </p>
                <div :if={package.diagnostic} class="alert alert-error mt-3 py-2 text-xs">
                  <span>Startup diagnostic: {package.diagnostic}</span>
                </div>
                <div :if={package.archive_digest} class="card-actions mt-4 justify-end">
                  <button
                    :if={package.previous_archive_digest}
                    phx-click="open_package_rollback"
                    phx-value-id={package.id}
                    class="btn btn-outline btn-sm"
                  >Rollback</button>
                  <button
                    phx-click="open_package_uninstall"
                    phx-value-id={package.id}
                    class="btn btn-error btn-outline btn-sm"
                    disabled={package.instances != []}
                    title={
                      if package.instances == [],
                        do: "Uninstall this package",
                        else: "Archive/export and permanently purge all instances first"
                    }
                  >Uninstall</button>
                </div>
                <p
                  :if={package.instances != [] && package.archive_digest}
                  class="mt-2 text-right text-xs text-base-content/50"
                >
                  {length(package.instances)} instance(s) must be removed before uninstall.
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
                    <p :if={instance.slug} class="mt-1 font-mono text-xs text-base-content/45">
                      /i/{instance.slug}
                    </p>
                  </div>
                  <span :if={instance.active} class="badge badge-primary gap-2">
                    <span class="size-2 animate-pulse rounded-full bg-primary-content"></span> Active
                  </span>
                  <span :if={!instance.active} class="badge badge-ghost">Stopped</span>
                </div>

                <div class="card-actions mt-5 justify-end">
                  <.link href={~p"/i/#{instance.id}/artwork"} class="btn btn-ghost btn-sm">Artwork intake</.link>
                  <.link href={~p"/i/#{instance.id}/moments"} class="btn btn-ghost btn-sm">Moments</.link>
                  <.link href={~p"/i/#{instance.id}/messages"} class="btn btn-ghost btn-sm">Messages</.link>
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

                <form
                  phx-submit="set_participant_code"
                  class="mt-4 flex flex-wrap items-end gap-2 border-t border-base-200 pt-4"
                >
                  <input type="hidden" name="instance_id" value={instance.id} />
                  <label class="form-control min-w-48 flex-1">
                    <span class="label-text text-xs font-semibold">Participant upload code</span>
                    <input
                      name="code"
                      type="password"
                      inputmode="numeric"
                      pattern="[0-9]{6}"
                      maxlength="6"
                      placeholder={
                        if instance.participant_code_digest,
                          do: "New six-digit code",
                          else: "Empty means open"
                      }
                      class="input input-bordered input-sm"
                    />
                  </label>
                  <button class="btn btn-outline btn-sm">{if instance.participant_code_digest,
                    do: "Change / clear",
                    else: "Set code"}</button>
                </form>

                <details class="collapse-arrow collapse mt-4 border border-base-200 bg-base-200/30">
                  <summary class="collapse-title min-h-0 py-3 text-sm font-semibold">
                    Participant QR codes
                  </summary>
                  <div class="collapse-content grid gap-4 sm:grid-cols-2">
                    <figure class="rounded-box bg-white p-3 text-center">
                      <img
                        src={~p"/manage/qr?#{[path: "/i/#{instance.id}/artwork"]}"}
                        alt="QR code for artwork intake"
                        class="mx-auto aspect-square w-full max-w-48"
                      />
                      <figcaption class="mt-2 text-sm font-semibold">Artwork intake</figcaption>
                    </figure>
                    <figure class="rounded-box bg-white p-3 text-center">
                      <img
                        src={~p"/manage/qr?#{[path: "/i/#{instance.id}/moments"]}"}
                        alt="QR code for Workshop Moments upload"
                        class="mx-auto aspect-square w-full max-w-48"
                      />
                      <figcaption class="mt-2 text-sm font-semibold">Workshop Moments</figcaption>
                    </figure>
                    <figure class="rounded-box bg-white p-3 text-center">
                      <img
                        src={~p"/manage/qr?#{[path: "/i/#{instance.id}/messages"]}"}
                        alt="QR code for visitor messages"
                        class="mx-auto aspect-square w-full max-w-48"
                      />
                      <figcaption class="mt-2 text-sm font-semibold">Messages</figcaption>
                    </figure>
                    <p class="text-xs text-base-content/55 sm:col-span-2">
                      These codes use the hostname or LAN address currently open in this browser. Open Management through the kiosk's LAN address before presenting them to participants.
                    </p>
                  </div>
                </details>
              </div>
            </article>
          </div>
        </section>

        <section class="card border border-base-300 bg-base-200/40">
          <div class="card-body">
            <h2 class="card-title">Import a workshop instance</h2>
            <p class="text-sm text-base-content/60">
              Move a complete workshop, including its Experience database and media, from another WakeCanvas installation. Imports remain archived until you restore them.
            </p>
            <form
              phx-change="validate_instance_import"
              phx-submit="import_instance"
              class="mt-3 grid gap-4 lg:grid-cols-[minmax(16rem,1fr)_12rem_minmax(14rem,1fr)_auto] lg:items-end"
            >
              <label class="form-control">
                <span class="label-text text-xs font-semibold">.wakecanvas-instance archive</span>
                <.live_file_input
                  upload={@uploads.instance_archive}
                  class="file-input file-input-bordered"
                />
              </label>
              <label class="form-control">
                <span class="label-text text-xs font-semibold">UUID collision</span>
                <select name="mode" class="select select-bordered" value={@instance_import_mode}>
                  <option value="preserve" selected={@instance_import_mode == "preserve"}>
                    Stop and report
                  </option>
                  <option value="clone" selected={@instance_import_mode == "clone"}>
                    Create a copy
                  </option>
                  <option value="replace" selected={@instance_import_mode == "replace"}>
                    Replace archived
                  </option>
                </select>
              </label>
              <label class="form-control">
                <span class="label-text text-xs font-semibold">
                  Existing instance name (replace only)
                </span>
                <input
                  name="confirmation"
                  value={@instance_import_confirmation}
                  disabled={@instance_import_mode != "replace"}
                  placeholder="Exact name confirms replacement"
                  autocomplete="off"
                  class="input input-bordered"
                />
              </label>
              <button
                class="btn btn-primary"
                disabled={@uploads.instance_archive.entries == []}
              >Import archived</button>
            </form>
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
                <div class="flex gap-2">
                  <.link
                    href={~p"/manage/instances/#{instance.id}/export"}
                    class="btn btn-ghost btn-sm"
                  >Export</.link>
                  <button
                    phx-click="restore"
                    phx-value-id={instance.id}
                    class="btn btn-outline btn-sm"
                  >Restore</button>
                  <button
                    phx-click="open_purge"
                    phx-value-id={instance.id}
                    class="btn btn-error btn-outline btn-sm"
                  >Permanently delete</button>
                </div>
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
              class="mt-3 grid gap-4 lg:grid-cols-[1fr_1fr_1fr_auto] lg:items-end"
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
                options={
                  @packages
                  |> Enum.filter(&(&1.status == "installed"))
                  |> Enum.map(&{&1.name, &1.id})
                }
              />
              <.input
                field={@form[:slug]}
                label="Optional URL alias"
                placeholder="saturday-workshop"
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

      <dialog :if={@rollback_candidate} open class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Rollback {@rollback_candidate.name}?</h3>
          <p class="py-4 text-base-content/70">
            The previously retained package will be selected. Instance content is not rolled back. Restart WakeCanvas afterward to activate the previous code.
          </p>
          <div class="modal-action">
            <button phx-click="cancel_package_rollback" class="btn">Cancel</button>
            <button
              phx-click="rollback_package"
              phx-value-id={@rollback_candidate.id}
              class="btn btn-warning"
            >
              Stage rollback
            </button>
          </div>
        </div>
        <button
          phx-click="cancel_package_rollback"
          class="modal-backdrop"
          aria-label="Cancel rollback"
        >close</button>
      </dialog>

      <dialog :if={@uninstall_candidate} open class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Uninstall {@uninstall_candidate.name}?</h3>
          <p class="py-3 text-base-content/70">
            This permanently removes the installed and retained package files. It is allowed only when no active or archived instance references the package.
          </p>
          <form phx-change="validate_package_uninstall" phx-submit="uninstall_package">
            <input type="hidden" name="package_id" value={@uninstall_candidate.id} />
            <label class="form-control">
              <span class="label-text">Type <strong>{@uninstall_candidate.name}</strong> to confirm</span>
              <input
                name="confirmation"
                value={@uninstall_confirmation}
                autocomplete="off"
                class="input input-bordered"
              />
            </label>
            <div class="modal-action">
              <button type="button" phx-click="cancel_package_uninstall" class="btn">Cancel</button>
              <button
                class="btn btn-error"
                disabled={@uninstall_confirmation != @uninstall_candidate.name}
              >
                Permanently uninstall
              </button>
            </div>
          </form>
        </div>
        <button
          phx-click="cancel_package_uninstall"
          class="modal-backdrop"
          aria-label="Cancel uninstall"
        >close</button>
      </dialog>

      <dialog :if={@purge_candidate} open class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Permanently delete {@purge_candidate.name}?</h3>
          <p class="py-3 text-base-content/70">
            This removes the instance record, database, and every uploaded image. This cannot be undone.
          </p>
          <form phx-change="validate_purge" phx-submit="purge">
            <input type="hidden" name="instance_id" value={@purge_candidate.id} />
            <label class="form-control">
              <span class="label-text">Type <strong>{@purge_candidate.name}</strong> to confirm</span>
              <input
                name="confirmation"
                value={@purge_confirmation}
                autocomplete="off"
                class="input input-bordered"
              />
            </label>
            <div class="modal-action">
              <button type="button" phx-click="cancel_purge" class="btn">Cancel</button>
              <button class="btn btn-error" disabled={@purge_confirmation != @purge_candidate.name}>Permanently delete</button>
            </div>
          </form>
        </div>
        <button phx-click="cancel_purge" class="modal-backdrop" aria-label="Cancel permanent deletion">close</button>
      </dialog>
    </Layouts.app>
    """
  end

  defp package_error({:incompatible, name, current, required}),
    do: "Package requires #{name} #{required}; this kiosk has #{current}."

  defp package_error({:unsafe_path, _}), do: "Package contains an unsafe file path."

  defp package_error({:incompatible_target, current, required}),
    do: "Package targets #{required}; this kiosk is #{current}."

  defp package_error({:module_collision, modules}),
    do:
      "Package contains modules already owned by WakeCanvas or another Experience: #{Enum.join(modules, ", ")}"

  defp package_error(:checksum_mismatch), do: "Package checksum validation failed."
  defp package_error(:invalid_manifest), do: "Package manifest is incomplete or invalid."
  defp package_error(:no_rollback_available), do: "No previous package is available."
  defp package_error(:confirmation_mismatch), do: "Type the exact package name to confirm."

  defp package_error(:source_linked_package),
    do: "Source-linked development packages cannot be uninstalled here."

  defp package_error({:instances_exist, count}),
    do: "This package still has #{count} active or archived instance(s). Remove them first."

  defp package_error(reason), do: "Package was rejected: #{inspect(reason)}"

  defp import_mode("clone"), do: :clone
  defp import_mode("replace"), do: :replace
  defp import_mode(_), do: :preserve

  defp instance_archive_error(:instance_exists),
    do:
      "That instance UUID already exists. Choose Create a copy, or replace the archived instance."

  defp instance_archive_error(:not_archived),
    do: "Only an archived instance can be replaced. Stop and archive it first."

  defp instance_archive_error(:confirmation_mismatch),
    do: "Type the exact existing instance name to confirm replacement."

  defp instance_archive_error({:package_not_installed, id}),
    do: "Install and restart Experience #{id} before importing this instance."

  defp instance_archive_error({:package_version_mismatch, installed, required}),
    do: "This archive needs Experience version #{required}; this kiosk has #{installed}."

  defp instance_archive_error(:checksum_mismatch),
    do: "The instance archive is damaged or has been modified."

  defp instance_archive_error(:invalid_manifest),
    do: "The instance archive metadata is invalid."

  defp instance_archive_error({:unsafe_path, _}),
    do: "The instance archive contains an unsafe file path."

  defp instance_archive_error(reason), do: "Could not import the instance: #{inspect(reason)}"

  defp find_package(socket, id), do: Enum.find(socket.assigns.packages, &(&1.id == id))

  defp diagnostic_badge_class(:ok), do: "badge badge-success badge-outline"
  defp diagnostic_badge_class(:warning), do: "badge badge-warning badge-outline"
  defp diagnostic_badge_class(:error), do: "badge badge-error"

  defp format_duration(seconds) do
    days = div(seconds, 86_400)
    hours = seconds |> rem(86_400) |> div(3_600)
    minutes = seconds |> rem(3_600) |> div(60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{minutes}m"
      true -> "#{minutes}m"
    end
  end
end
