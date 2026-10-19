defmodule WakeCanvas.Experiences.RegistryTest do
  use ExUnit.Case, async: true

  alias WakeCanvas.ExperienceSDK.{Definition, DisplayVariant, Surface}
  alias WakeCanvas.Experiences.Registry

  test "accepts a compiled definition that matches its package manifest" do
    assert :ok = Registry.validate_definition(definition(), manifest())
  end

  test "identifies the mismatched contract field without exposing package internals" do
    changed =
      put_in(manifest(), ["displayVariants", Access.at(0), "entrypoint"], "static/other.js")

    assert {:error, {:definition_manifest_mismatch, :display_variants}} =
             Registry.validate_definition(definition(), changed)
  end

  defp definition do
    %Definition{
      id: "org.example.demo",
      name: "Demo",
      version: "1.0.0",
      otp_application: :demo,
      stylesheet: "static/experience.css",
      capabilities: [:camera, :participant_devices],
      surfaces: [
        %Surface{id: :display, path: "display", module: Demo.DisplayLive, role: :display}
      ],
      default_display_variant: "default",
      display_variants: [
        %DisplayVariant{
          id: "default",
          label: "Default",
          description: "Demo",
          entrypoint: "static/default.js",
          capabilities: [:webgl],
          fallback: nil
        }
      ]
    }
  end

  defp manifest do
    %{
      "experienceId" => "org.example.demo",
      "name" => "Demo",
      "version" => "1.0.0",
      "otpApplication" => "demo",
      "capabilities" => ["camera", "participant-devices"],
      "browser" => %{"stylesheet" => "static/experience.css"},
      "surfaces" => [
        %{
          "id" => "display",
          "path" => "display",
          "module" => "Demo.DisplayLive",
          "role" => "display"
        }
      ],
      "defaultDisplayVariant" => "default",
      "displayVariants" => [
        %{
          "id" => "default",
          "entrypoint" => "static/default.js",
          "capabilities" => ["webgl"]
        }
      ]
    }
  end
end
