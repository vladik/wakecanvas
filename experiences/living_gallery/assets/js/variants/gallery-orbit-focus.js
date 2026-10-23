import {mountWithOptions} from "./gallery-orbit.js"

export async function mount(container, initial) {
  return mountWithOptions(container, initial, {focus: true})
}
