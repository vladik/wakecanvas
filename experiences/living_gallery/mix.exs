defmodule WakeCanvas.Experience.LivingGallery.MixProject do
  use Mix.Project

  def project do
    [
      app: :wake_canvas_experience_living_gallery,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WakeCanvas.Experience.LivingGallery.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:wake_canvas_experience_sdk, path: "../sdk"},
      {:phoenix_live_view, "~> 1.2"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        &copy_static/1,
        "tailwind living_gallery",
        "esbuild living_gallery",
        "esbuild living_gallery_media",
        "compile --force"
      ],
      "assets.deploy": [
        &copy_static/1,
        "tailwind living_gallery --minify",
        "esbuild living_gallery --minify",
        "esbuild living_gallery_media --minify",
        "compile --force"
      ]
    ]
  end

  defp copy_static(_args) do
    source = Path.expand("assets/static", __DIR__)
    destination = Path.expand("priv/static", __DIR__)
    File.mkdir_p!(destination)
    File.cp_r!(source, destination)
    :ok
  end
end
