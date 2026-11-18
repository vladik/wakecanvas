import Config

config :wake_canvas_experience_collective_form,
  ecto_repos: [WakeCanvas.Experience.CollectiveForm.Repo]

config :esbuild,
  version: "0.25.4",
  collective_form: [
    args: ~w(
      js/variants/growing-mycelium.js
      js/variants/growing-mycelium-creature-reveals.js
      --bundle
      --format=esm
      --target=es2022
      --loader:.svg=text
      --outdir=../priv/static/variants
    ),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" => [
        Path.expand("../node_modules", __DIR__),
        Path.expand("../deps", __DIR__),
        Mix.Project.build_path()
      ]
    }
  ]
