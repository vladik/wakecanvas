defmodule Mix.Tasks.Wakecanvas.Package.Verify do
  use Mix.Task

  @shortdoc "Validates and smoke-loads a .wakecanvas package"

  @impl Mix.Task
  def run([archive_path]) do
    Mix.Task.run("compile")

    case WakeCanvas.Experiences.PackageSmoke.verify(Path.expand(archive_path)) do
      {:ok, result} ->
        Mix.shell().info(
          "Verified #{result.name} #{result.version} (#{result.experience_id}, #{result.modules} modules)"
        )

        Mix.shell().info("SHA-256 #{result.digest}")

      {:error, reason} ->
        Mix.raise("package smoke check failed: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix wakecanvas.package.verify PATH")
end
