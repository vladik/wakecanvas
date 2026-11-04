import {mountWithOptions} from "./gallery-orbit.js"

export function mount(container, initial) {
  return mountWithOptions(container, initial, {focus: true, cinema: true})
}
