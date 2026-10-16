# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     WakeCanvas.Repo.insert!(%WakeCanvas.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias WakeCanvas.Experiences.{Instance, Package}
alias WakeCanvas.Repo

package =
  Repo.get(Package, "org.wakecanvas.experience.living-gallery") ||
    Repo.insert!(%Package{
      id: "org.wakecanvas.experience.living-gallery",
      name: "Living Gallery",
      version: "0.1.0"
    })

if Repo.aggregate(Instance, :count) == 0 do
  Repo.insert!(%Instance{name: "Morning Workshop", package: package, active: true})
  Repo.insert!(%Instance{name: "Evening Workshop", package: package})
end
