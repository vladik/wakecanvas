defmodule WakeCanvas.Experience.CollectiveForm.MixProject do
  use Mix.Project

  def project do
    [
      app: :wake_canvas_experience_collective_form,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {WakeCanvas.Experience.CollectiveForm.Application, []}]
  end

  defp deps do
    [
      {:wake_canvas_experience_sdk, path: "../sdk"},
      {:phoenix_live_view, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild collective_form", &copy_stylesheet/1, "compile --force"],
      "assets.deploy": ["esbuild collective_form --minify", &copy_stylesheet/1, "compile --force"]
    ]
  end

  defp copy_stylesheet(_args) do
    destination = Path.expand("priv/static/experience.css", __DIR__)
    File.mkdir_p!(Path.dirname(destination))
    File.cp!(Path.expand("assets/css/experience.css", __DIR__), destination)
  end
end
