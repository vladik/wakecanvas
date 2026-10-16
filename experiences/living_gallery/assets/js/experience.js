/** Living Gallery browser renderer entry point. */
export function mount(container, context = {}) {
  return {
    handleEvent(_name, _payload) {},
    destroy() {
      container.replaceChildren();
    },
    context,
  };
}
