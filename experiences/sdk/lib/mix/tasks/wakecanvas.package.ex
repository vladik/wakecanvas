defmodule Mix.Tasks.Wakecanvas.Package do
  use Mix.Task

  @shortdoc "Builds a deterministic .wakecanvas Experience package"

  @switches [manifest: :string, output: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")
    {options, remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if remaining != [] or invalid != [] do
      Mix.raise("usage: mix wakecanvas.package [--manifest PATH] [--output PATH]")
    end

    project = Mix.Project.config()
    manifest = options[:manifest] || "wakecanvas-experience.json"
    app = project |> Keyword.fetch!(:app) |> Atom.to_string()
    version = Keyword.fetch!(project, :version)

    output =
      options[:output] ||
        Path.join([Mix.Project.build_path(), "wakecanvas", "#{app}-#{version}.wakecanvas"])

    case WakeCanvas.ExperienceSDK.PackageBuilder.build(
           manifest,
           Mix.Project.app_path(),
           output
         ) do
      {:ok, result} ->
        Mix.shell().info("Built #{result.path}")
        Mix.shell().info("SHA-256 #{result.digest}")

      {:error, reason} ->
        Mix.raise("could not build package: #{inspect(reason)}")
    end
  end
end
