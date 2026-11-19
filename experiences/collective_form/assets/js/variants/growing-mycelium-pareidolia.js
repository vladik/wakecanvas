import {mountMycelium} from "./growing-mycelium.js"
import {createPareidoliaReveal} from "./mycelium/pareidolia-reveal.js"

export async function mount(container, initialSnapshot) {
  return mountMycelium(container, initialSnapshot, {
    revealMode: "pareidolia",
    createReveal: createPareidoliaReveal,
  })
}
