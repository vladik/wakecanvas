defmodule WakeCanvasWeb.ManageLive do
  use WakeCanvasWeb, :live_view

  alias WakeCanvas.Diagnostics
  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.ActiveInstanceManager
  alias WakeCanvas.Experiences.Instance
  alias WakeCanvas.Experiences.Registry

  @impl true
  def mount(params, _session, socket) do
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
     |> assign(:section, management_section(params["section"]))
     |> assign(:edit_candidate, nil)
     |> assign(:edit_form, nil)
     |> assign(:rollback_candidate, nil)
     |> assign(:uninstall_candidate, nil)
     |> assign(:uninstall_confirmation, "")
     |> assign(:archive_candidate, nil)
     |> assign(:purge_candidate, nil)
     |> assign(:purge_confirmation, "")
     |> assign(:diagnostics, Diagnostics.snapshot())
     |> refresh()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :section, management_section(params["section"]))}
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
    availability = if Map.get(params, "keep_archived") == "true", do: :archived, else: :available

    results =
      consume_uploaded_entries(socket, :instance_archive, fn %{path: path}, _entry ->
        {:ok, Experiences.import_instance(path, import_mode(mode), confirmation, availability)}
      end)

    case results do
      [{:ok, {:ok, instance}}] ->
        message =
          if availability == :archived,
            do: "#{instance.name} was imported into Archived instances.",
            else: "#{instance.name} is ready. Review its settings and click Start when ready."

        {:noreply,
         socket
         |> assign(:instance_import_confirmation, "")
         |> put_flash(:info, message)
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

  def handle_event("open_instance_details", %{"id" => id}, socket) do
    candidate = Enum.find(socket.assigns.instances, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:edit_candidate, candidate)
     |> assign(
       :edit_form,
       to_form(Experiences.change_instance_details(candidate), as: :edit_instance)
     )}
  end

  def handle_event("cancel_instance_details", _params, socket) do
    {:noreply, socket |> assign(:edit_candidate, nil) |> assign(:edit_form, nil)}
  end

  def handle_event("validate_instance_details", %{"edit_instance" => params}, socket) do
    form =
      socket.assigns.edit_candidate
      |> Experiences.change_instance_details(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :edit_instance)

    {:noreply, assign(socket, :edit_form, form)}
  end

  def handle_event("save_instance_details", %{"edit_instance" => params}, socket) do
    case Experiences.update_instance_details(socket.assigns.edit_candidate, params) do
      {:ok, instance} ->
        {:noreply,
         socket
         |> assign(:edit_candidate, nil)
         |> assign(:edit_form, nil)
         |> put_flash(:info, "#{instance.name} details were updated.")
         |> refresh()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :edit_form, to_form(changeset, action: :update, as: :edit_instance))}
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
            <h1 class="mt-2 text-4xl font-bold tracking-tight">Kiosk management</h1>
            <p class="mt-3 max-w-2xl text-base-content/65">
              {management_section_description(@section)}
            </p>
          </div>
          <.link href={~p"/display"} class="btn btn-primary btn-lg">
            <span :if={@active_variant}>Open active display · {@active_variant.label}</span>
            <span :if={!@active_variant}>Open active display</span>
          </.link>
        </section>

        <nav class="tabs-box tabs overflow-x-auto bg-base-200 p-1" aria-label="Management sections">
          <.link navigate={~p"/manage"} class={management_tab_class(@section, "workshops")}>
            Workshops
          </.link>
          <.link
            navigate={~p"/manage/import"}
            class={management_tab_class(@section, "import")}
          >
            Import & archive
          </.link>
          <.link
            navigate={~p"/manage/experiences"}
            class={management_tab_class(@section, "experiences")}
          >
            Experiences
          </.link>
          <.link
            navigate={~p"/manage/system"}
            class={management_tab_class(@section, "system")}
          >
            System
          </.link>
        </nav>

        <section :if={@section == "workshops"} class="alert border border-base-300 bg-base-100">
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

        <section
          :if={@section == "system"}
          class="card border border-base-300 bg-base-100 shadow-sm"
        >
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

        <section :if={@section == "experiences"}>
          <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 class="text-xl font-semibold">Experience packages</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Install a validated package built by an Experience developer. Activation happens after restart.
              </p>
            </div>
            <form
              id="install-experience-form"
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

        <section :if={@section == "workshops"}>
          <div class="mb-4 flex items-center justify-between">
            <div>
              <h2 class="text-xl font-semibold">Workshops</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Each workshop has independent content and presentation settings.
              </p>
            </div>
            <span class="badge badge-neutral">{length(@instances)} available</span>
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
                    <p class="text-sm text-base-content/60">Experience: {instance.package.name}</p>
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
                  <button
                    phx-click="open_instance_details"
                    phx-value-id={instance.id}
                    class="btn btn-ghost btn-sm"
                  >Edit details</button>
                  <.link
                    href={~p"/i/#{Experiences.instance_reference(instance)}/artwork"}
                    class="btn btn-ghost btn-sm"
                  >Artwork intake</.link>
                  <.link
                    href={~p"/i/#{Experiences.instance_reference(instance)}/moments"}
                    class="btn btn-ghost btn-sm"
                  >Moments</.link>
                  <.link
                    href={~p"/i/#{Experiences.instance_reference(instance)}/messages"}
                    class="btn btn-ghost btn-sm"
                  >Messages</.link>
                  <.link
                    href={~p"/i/#{Experiences.instance_reference(instance)}/review"}
                    class="btn btn-ghost btn-sm"
                  >Review</.link>
                  <.link
                    href={~p"/i/#{Experiences.instance_reference(instance)}/settings"}
                    class="btn btn-ghost btn-sm"
                  >Presentation settings</.link>
                  <.link
                    href={~p"/i/#{Experiences.instance_reference(instance)}/display"}
                    class="btn btn-ghost btn-sm"
                  >
                    Preview
                  </.link>
                  <.link
                    href={~p"/manage/instances/#{instance.id}/export"}
                    class="btn btn-outline btn-sm"
                  >Export</.link>
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

                <details
                  id={"participant-qr-#{instance.id}"}
                  class="collapse-arrow collapse mt-4 border border-base-200 bg-base-200/30"
                >
                  <summary class="collapse-title min-h-0 py-3 pr-12">
                    <span class="block text-sm font-semibold">Share with participants</span>
                    <span class="mt-0.5 block text-xs font-normal text-base-content/60">
                      Three QR codes for artwork, workshop photos, and visitor messages
                    </span>
                  </summary>
                  <div class="collapse-content space-y-3">
                    <article
                      :for={destination <- participant_qr_destinations(instance)}
                      id={"participant-qr-#{instance.id}-#{destination.id}"}
                      class="rounded-box border border-base-300 bg-base-100 p-4"
                    >
                      <div class="grid items-center gap-4 sm:grid-cols-[minmax(0,1fr)_11rem]">
                        <div class="min-w-0">
                          <div class="mb-2 flex flex-wrap items-center gap-2">
                            <h4 class="font-semibold">{destination.title}</h4>
                            <span class="badge badge-outline badge-sm">{destination.audience}</span>
                          </div>
                          <p class="text-sm leading-relaxed text-base-content/70">
                            {destination.description}
                          </p>
                          <p class="mt-3 break-all rounded bg-base-200 px-2 py-1 font-mono text-xs text-base-content/70">
                            {destination.path}
                          </p>
                          <.link
                            href={destination.path}
                            target="_blank"
                            rel="noopener"
                            class="btn btn-outline btn-sm mt-3"
                          >
                            Open page
                          </.link>
                        </div>
                        <figure class="rounded-box justify-self-center bg-white p-2 shadow-sm">
                          <img
                            src={~p"/manage/qr?#{[path: destination.path]}"}
                            alt={"QR code for #{destination.title}"}
                            class="aspect-square w-40"
                          />
                        </figure>
                      </div>
                    </article>

                    <div class="alert py-3 text-xs">
                      <span>
                        QR codes use the address currently open in this browser. Before sharing them, open Management using this kiosk's LAN address—not localhost—so participant phones can connect.
                      </span>
                    </div>
                  </div>
                </details>
              </div>
            </article>
          </div>
        </section>

        <section
          :if={@section == "import"}
          class="card border border-base-300 bg-base-200/40"
        >
          <div class="card-body">
            <h2 class="card-title">Import workshop</h2>
            <p class="text-sm text-base-content/60">
              Add an exported workshop with all of its settings and media. It will be available but stopped, so you can review it before clicking Start.
            </p>
            <form
              id="import-workshop-form"
              phx-change="validate_instance_import"
              phx-submit="import_instance"
              class="mt-3 space-y-4"
            >
              <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
                <label class="form-control min-w-0 flex-1">
                  <span class="label-text text-xs font-semibold">Workshop file</span>
                  <.live_file_input
                    upload={@uploads.instance_archive}
                    class="file-input file-input-bordered w-full"
                  />
                </label>
                <button
                  class="btn btn-primary"
                  disabled={@uploads.instance_archive.entries == []}
                >Import workshop</button>
              </div>

              <details class="collapse-arrow collapse border border-base-300 bg-base-100">
                <summary class="collapse-title min-h-0 py-3 text-sm font-semibold">
                  Advanced import options
                </summary>
                <div class="collapse-content grid gap-4 lg:grid-cols-3 lg:items-end">
                  <label class="form-control">
                    <span class="label-text text-xs font-semibold">If the UUID already exists</span>
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
                      Existing workshop name (replace only)
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
                  <label class="label cursor-pointer justify-start gap-3 rounded-box border border-base-300 px-4 py-3">
                    <input
                      type="checkbox"
                      name="keep_archived"
                      value="true"
                      class="checkbox checkbox-sm"
                    />
                    <span class="label-text">Keep in Archived instances after import</span>
                  </label>
                </div>
              </details>
            </form>
          </div>
        </section>

        <section
          :if={@section == "import" && @archived_instances != []}
          class="card border border-base-300 bg-base-200/40"
        >
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

        <section
          :if={@section == "workshops"}
          class="card border border-base-300 bg-base-200/40"
        >
          <div class="card-body">
            <h2 class="card-title">Create workshop</h2>
            <.form
              for={@form}
              id="create-workshop-form"
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

      <dialog :if={@edit_candidate} open class="modal modal-open">
        <div class="modal-box">
          <h3 class="text-lg font-bold">Edit workshop details</h3>
          <p class="py-3 text-sm text-base-content/65">
            Rename this workshop or give it a memorable URL alias. Its UUID, Experience, content, and presentation settings will not change.
          </p>
          <.form
            for={@edit_form}
            id="edit-workshop-form"
            phx-change="validate_instance_details"
            phx-submit="save_instance_details"
            class="space-y-4"
          >
            <.input field={@edit_form[:name]} label="Workshop name" />
            <.input
              field={@edit_form[:slug]}
              label="Optional URL alias"
              placeholder="saturday-workshop"
            />
            <div class="rounded-box bg-base-200/60 p-3 text-xs text-base-content/60">
              Experience: {@edit_candidate.package.name} · Stable ID: {@edit_candidate.id}
            </div>
            <div class="modal-action">
              <button type="button" phx-click="cancel_instance_details" class="btn">Cancel</button>
              <button class="btn btn-primary">Save details</button>
            </div>
          </.form>
        </div>
        <button
          phx-click="cancel_instance_details"
          class="modal-backdrop"
          aria-label="Cancel editing workshop details"
        >close</button>
      </dialog>

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

  defp management_section(section)
       when section in ["workshops", "import", "experiences", "system"],
       do: section

  defp management_section(_), do: "workshops"

  defp management_tab_class(current, section),
    do: ["tab whitespace-nowrap", current == section && "tab-active"]

  defp management_section_description("workshops"),
    do: "Configure, preview, and choose the workshop shown on this kiosk."

  defp management_section_description("import"),
    do: "Move complete workshops between WakeCanvas installations and manage archived work."

  defp management_section_description("experiences"),
    do: "Review, install, update, or remove the Experience packages available on this kiosk."

  defp management_section_description("system"),
    do: "Check storage, runtime, package, and renderer health for this installation."

  defp participant_qr_destinations(instance) do
    prefix = "/i/#{Experiences.instance_reference(instance)}"

    [
      %{
        id: "artwork",
        title: "Add an artwork",
        audience: "Participants",
        description:
          "Photograph or upload a finished artwork and optionally add the creator's name. Use this at the artwork intake station.",
        path: "#{prefix}/artwork"
      },
      %{
        id: "moments",
        title: "Add workshop moments",
        audience: "Facilitator / photographer",
        description:
          "Upload atmosphere and activity photos from the workshop. These may wait for review before appearing on the wall.",
        path: "#{prefix}/moments"
      },
      %{
        id: "messages",
        title: "Leave a message",
        audience: "Visitors",
        description:
          "Submit a short message or testimonial that the Experience can include in the shared presentation.",
        path: "#{prefix}/messages"
      }
    ]
  end

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
