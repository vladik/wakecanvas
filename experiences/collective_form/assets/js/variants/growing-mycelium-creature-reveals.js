import {mountMycelium} from "./growing-mycelium.js"
import {createCreatureReveal} from "./mycelium/creature-reveal.js"

export async function mount(container, initialSnapshot) {
  return mountMycelium(container, initialSnapshot, {
    revealMode: "creature",
    createReveal: createCreatureReveal,
  })
}
