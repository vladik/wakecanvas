defmodule Mix.Tasks.Wakecanvas.New do
  use Mix.Task

  @shortdoc "Generates a standalone WakeCanvas Experience project"
  @switches [module: :string, app: :string, id: :string, name: :string, sdk_path: :string]

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] or length(positional) != 1 do
      usage!()
    end

    [destination] = positional
    basename = destination |> Path.basename() |> String.replace(~r/[^A-Za-z0-9_-]/, "_")
    app = options[:app] || Macro.underscore(basename)
    module = options[:module] || Macro.camelize(app)
    id = options[:id] || "org.example.experience.#{String.replace(app, "_", "-")}"
    name = options[:name] || humanize(app)
    sdk_path = options[:sdk_path] || File.cwd!()

    case WakeCanvas.ExperienceSDK.ProjectGenerator.generate(destination,
           app: app,
           module: module,
           id: id,
           name: name,
           sdk_path: sdk_path
         ) do
      {:ok, path} ->
        Mix.shell().info("Created #{path}")
        Mix.shell().info("Next: cd #{path} && mix deps.get && mix test")

      {:error, :destination_not_empty} ->
        Mix.raise("destination exists and is not empty")

      {:error, :invalid_identifier} ->
        Mix.raise("app, module, or Experience ID has an invalid format")

      {:error, reason} ->
        Mix.raise("could not generate Experience: #{inspect(reason)}")
    end
  end

  defp usage! do
    Mix.raise(
      "usage: mix wakecanvas.new PATH [--module Demo.Experience] [--app demo_experience] " <>
        "[--id org.example.experience.demo] [--name \"Demo Experience\"] [--sdk-path PATH]"
    )
  end

  defp humanize(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
