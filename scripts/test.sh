#!/usr/bin/env sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for project in experiences/sdk experiences/living_gallery platform; do
  (
    cd "$repository_root/$project"
    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test
  )
done
