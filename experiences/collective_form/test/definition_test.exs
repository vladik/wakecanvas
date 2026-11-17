defmodule WakeCanvas.Experience.CollectiveForm.DefinitionTest do
  use ExUnit.Case, async: true

  test "exposes a packageable Experience definition" do
    definition = WakeCanvas.Experience.CollectiveForm.definition()
    assert definition.id == "org.wakecanvas.experience.collective-form"
    assert definition.default_display_variant == "growing-mycelium"
    assert [%{id: "growing-mycelium"}] = definition.display_variants
    assert definition.config_schema["placement_source"].default == "operator"
    assert Enum.map(definition.surfaces, & &1.path) == ["display", "contribute", "table"]
  end
end
