defmodule WakeCanvas.ExperienceSDK.ProjectGenerator do
  @moduledoc "Generates a standalone, package-ready WakeCanvas Experience project."

  def generate(destination, options) do
    destination = Path.expand(destination)
    app = Keyword.fetch!(options, :app)
    module = Keyword.fetch!(options, :module)
    id = Keyword.fetch!(options, :id)
    name = Keyword.fetch!(options, :name)
    sdk_path = options |> Keyword.fetch!(:sdk_path) |> Path.expand() |> String.replace("\\", "/")

    with :ok <- validate_identifiers(app, module, id),
         :ok <- ensure_empty_destination(destination) do
      assigns = %{app: app, module: module, id: id, name: name, sdk_path: sdk_path}

      files(assigns)
      |> Enum.each(fn {relative, contents} ->
        path = Path.join(destination, relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, contents, [:exclusive])
      end)

      {:ok, destination}
    end
  end

  defp validate_identifiers(app, module, id) do
    valid =
      Regex.match?(~r/^[a-z][a-z0-9_]*$/, app) and
        Regex.match?(~r/^[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*$/, module) and
        Regex.match?(~r/^[a-z0-9]+(?:[._-][a-z0-9]+)+$/, id)

    if valid, do: :ok, else: {:error, :invalid_identifier}
  end

  defp ensure_empty_destination(destination) do
    case File.ls(destination) do
      {:ok, []} -> :ok
      {:ok, _files} -> {:error, :destination_not_empty}
      {:error, :enoent} -> File.mkdir_p(destination)
      {:error, reason} -> {:error, reason}
    end
  end

  defp files(a) do
    module_path = a.module |> Macro.underscore()

    %{
      ".formatter.exs" =>
        "[inputs: [\"{mix,.formatter}.exs\", \"{config,lib,test}/**/*.{ex,exs}\"]]\n",
      ".gitignore" => "/_build/\n/deps/\n*.wakecanvas\n",
      "mix.exs" => mix_exs(a),
      "README.md" => readme(a),
      "wakecanvas-experience.json" => manifest(a),
      "lib/#{module_path}.ex" => entry_module(a),
      "lib/#{module_path}/application.ex" => application_module(a),
      "lib/#{module_path}/display_live.ex" => display_live(a),
      "priv/static/experience.css" => stylesheet(),
      "priv/static/variants/default.js" => renderer(),
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/definition_test.exs" => definition_test(a)
    }
  end

  defp mix_exs(a) do
    """
    defmodule #{a.module}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{a.app},
          version: "0.1.0",
          elixir: "~> 1.20",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [extra_applications: [:logger], mod: {#{a.module}.Application, []}]
      end

      defp deps do
        [
          {:wake_canvas_experience_sdk, path: "#{a.sdk_path}"},
          {:phoenix_live_view, "~> 1.2"},
          {:jason, "~> 1.4"}
        ]
      end
    end
    """
  end

  defp entry_module(a) do
    """
    defmodule #{a.module} do
      @behaviour WakeCanvas.ExperienceSDK.Experience

      alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}

      @impl true
      def definition do
        %Definition{
          id: "#{a.id}",
          name: "#{escape(a.name)}",
          version: "0.1.0",
          otp_application: :#{a.app},
          stylesheet: "static/experience.css",
          surfaces: [
            %Surface{
              id: :display,
              path: "display",
              module: #{a.module}.DisplayLive,
              role: :display,
              label: "#{escape(a.name)} Display"
            }
          ],
          default_display_variant: "default",
          display_variants: [
            %DisplayVariant{
              id: "default",
              label: "Default",
              description: "Starter renderer",
              entrypoint: "static/variants/default.js"
            }
          ]
        }
      end

      @impl true
      def validate_config(config) when is_map(config), do: {:ok, config}
      def validate_config(_config), do: {:error, :invalid_config}
    end
    """
  end

  defp application_module(a) do
    """
    defmodule #{a.module}.Application do
      use Application

      @impl true
      def start(_type, _args) do
        Supervisor.start_link([], strategy: :one_for_one, name: #{a.module}.Supervisor)
      end
    end
    """
  end

  defp display_live(a) do
    ~s'''
    defmodule #{a.module}.DisplayLive do
      use Phoenix.LiveView

      @impl true
      def mount(_params, session, socket) do
        {:ok,
         socket
         |> assign(:instance_id, session["instance_id"])
         |> assign(:instance_name, session["instance_name"] || "#{escape(a.name)}")
         |> assign(:display_variant, session["display_variant"] || "default")
         |> assign(:renderer_diagnostics_api, session["renderer_diagnostics_api"])
         |> assign(:renderer_url, session["renderer_url"])
         |> assign(:stylesheet_url, session["experience_stylesheet_url"])}
      end

      @impl true
      def handle_event("renderer:diagnostic", payload, socket) do
        case socket.assigns.renderer_diagnostics_api do
          api when is_atom(api) ->
            if function_exported?(api, :report, 2), do: api.report(socket.assigns.instance_id, payload)

          _ ->
            :ok
        end

        {:noreply, socket}
      end

      @impl true
      def render(assigns) do
        ~H"""
        <link :if={@stylesheet_url} rel="stylesheet" href={@stylesheet_url} />
        <div
          id="experience-renderer"
          phx-hook="ExperienceRenderer"
          phx-update="ignore"
          data-display-variant={@display_variant}
          data-renderer-url={@renderer_url}
          data-renderer-capabilities="[]"
          data-renderer-context={Jason.encode!(%{instanceName: @instance_name})}
        >
          <p class="experience-loading">Preparing {@instance_name}...</p>
        </div>
        """
      end
    end
    '''
  end

  defp manifest(a) do
    Jason.encode!(
      %{
        "manifestVersion" => 1,
        "experienceId" => a.id,
        "name" => a.name,
        "version" => "0.1.0",
        "otpApplication" => a.app,
        "entryModule" => a.module,
        "target" => "any",
        "sdkRequirement" => ">= 0.1.0 and < 1.0.0",
        "platformRequirement" => ">= 0.1.0 and < 1.0.0",
        "elixirRequirement" => ">= 1.20.0 and < 2.0.0",
        "otpRequirement" => ">= 29.0.0 and < 30.0.0",
        "capabilities" => [],
        "defaultDisplayVariant" => "default",
        "displayVariants" => [
          %{
            "id" => "default",
            "label" => "Default",
            "description" => "Starter renderer",
            "entrypoint" => "static/variants/default.js"
          }
        ],
        "surfaces" => [
          %{
            "id" => "display",
            "path" => "display",
            "module" => "#{a.module}.DisplayLive",
            "role" => "display"
          }
        ],
        "browser" => %{
          "stylesheet" => "static/experience.css",
          "renderers" => "static/variants/*.js"
        }
      },
      pretty: true
    ) <> "\n"
  end

  defp stylesheet do
    """
    [data-wakecanvas-experience] { min-height: 100vh; }
    .experience-loading { color: white; font: 1.5rem system-ui, sans-serif; }
    .starter-canvas {
      min-height: 100vh; display: grid; place-items: center;
      color: white; background: radial-gradient(circle at top, #4f46e5, #111827 65%);
      font: clamp(2rem, 7vw, 6rem)/1 system-ui, sans-serif; text-align: center;
    }
    """
  end

  defp renderer do
    """
    export function mount(container, context) {
      const render = value => {
        container.innerHTML = `<main class="starter-canvas"><span>${value.instanceName}</span></main>`
      }
      render(context)
      return {
        update(next) { context = next; render(context) },
        resize() {},
        destroy() { container.replaceChildren() }
      }
    }
    """
  end

  defp definition_test(a) do
    """
    defmodule #{a.module}.DefinitionTest do
      use ExUnit.Case, async: true

      test "exposes a packageable Experience definition" do
        definition = #{a.module}.definition()
        assert definition.id == "#{a.id}"
        assert definition.default_display_variant == "default"
        assert [%{path: "display"}] = definition.surfaces
      end
    end
    """
  end

  defp readme(a) do
    """
    # #{a.name}

    Standalone WakeCanvas Experience generated from the SDK starter.

    ```powershell
    mix deps.get
    mix test
    mix wakecanvas.package
    ```

    Upload the resulting archive from `_build/wakecanvas/` in WakeCanvas Management,
    then restart the platform. Replace the path-based SDK dependency with your chosen
    Git or Hex source before sharing this project with another developer.
    """
  end

  defp escape(value), do: String.replace(value, "\"", "\\\"")
end
