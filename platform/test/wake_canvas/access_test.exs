defmodule WakeCanvas.AccessTest do
  use WakeCanvas.DataCase

  alias WakeCanvas.Access
  alias WakeCanvas.Experiences
  alias WakeCanvas.Experiences.Package
  alias WakeCanvas.Repo

  setup do
    package =
      Repo.insert!(%Package{
        id: "org.wakecanvas.access-test",
        name: "Access Test",
        version: "1.0.0"
      })

    {:ok, instance} =
      Experiences.create_instance(%{name: "Protected Workshop", experience_id: package.id})

    %{instance: instance}
  end

  test "an empty participant code leaves intake open", %{instance: instance} do
    conn = Plug.Test.init_test_session(Plug.Test.conn(:get, "/"), %{})
    assert Access.participant_open?(instance)
    assert Access.participant_authorized?(conn, instance)
  end

  test "a six-digit participant code verifies and rotation invalidates the old session", %{
    instance: instance
  } do
    assert {:ok, protected} = Experiences.set_participant_code(instance.id, "123456")
    refute Access.participant_open?(protected)
    assert Access.valid_participant_code?(protected, "123456")
    refute Access.valid_participant_code?(protected, "654321")

    conn = Plug.Test.init_test_session(Plug.Test.conn(:get, "/"), %{})
    refute Access.participant_authorized?(conn, protected)
    authorized = Access.authorize_participant(conn, protected)
    assert Access.participant_authorized?(authorized, protected)

    assert {:ok, rotated} = Experiences.set_participant_code(instance.id, "654321")
    refute Access.participant_authorized?(authorized, rotated)
    assert Access.valid_participant_code?(rotated, "654321")
  end

  test "participant codes are exactly six digits", %{instance: instance} do
    assert {:error, :invalid_code} = Experiences.set_participant_code(instance.id, "12345")
    assert {:error, :invalid_code} = Experiences.set_participant_code(instance.id, "secret")
  end

  test "the configured management code is exactly six digits" do
    previous = Application.get_env(:wake_canvas, :management_code, "")
    on_exit(fn -> Application.put_env(:wake_canvas, :management_code, previous) end)

    Application.put_env(:wake_canvas, :management_code, "123456")
    assert Access.verify_management_code("123456")
    refute Access.verify_management_code("654321")

    Application.put_env(:wake_canvas, :management_code, "not-six-digits")
    refute Access.verify_management_code("not-six-digits")
  end
end
