defmodule WakeCanvas.Access do
  @moduledoc false

  alias WakeCanvas.Experiences.Instance

  @iterations 120_000
  @management_session_key "wakecanvas_management_access"
  @participant_session_key "wakecanvas_participant_access"

  def management_open? do
    configured_management_code() == ""
  end

  def management_authorized?(conn) do
    management_open?() || Plug.Conn.get_session(conn, @management_session_key) == true
  end

  def authorize_management(conn),
    do: Plug.Conn.put_session(conn, @management_session_key, true)

  def clear_management(conn),
    do: Plug.Conn.delete_session(conn, @management_session_key)

  def verify_management_code(code) when is_binary(code) do
    expected = configured_management_code()
    Regex.match?(~r/^\d{6}$/, expected) && secure_compare(expected, String.trim(code))
  end

  def verify_management_code(_code), do: false

  def participant_open?(%Instance{participant_code_digest: digest}), do: digest in [nil, ""]

  def participant_authorized?(conn, %Instance{} = instance) do
    participant_open?(instance) ||
      conn
      |> Plug.Conn.get_session(@participant_session_key)
      |> then(fn sessions ->
        is_map(sessions) && sessions[instance.id] == instance.participant_code_version
      end)
  end

  def authorize_participant(conn, %Instance{} = instance) do
    sessions = Plug.Conn.get_session(conn, @participant_session_key) || %{}

    Plug.Conn.put_session(
      conn,
      @participant_session_key,
      Map.put(sessions, instance.id, instance.participant_code_version)
    )
  end

  def valid_participant_code?(%Instance{participant_code_digest: digest}, code)
      when is_binary(digest) and is_binary(code) do
    verify_code(digest, String.trim(code))
  end

  def valid_participant_code?(_instance, _code), do: false

  def participant_code_change(%Instance{} = instance, code) when is_binary(code) do
    normalized = String.trim(code)

    cond do
      normalized == "" ->
        {:ok,
         Ecto.Changeset.change(instance,
           participant_code_digest: nil,
           participant_code_version: instance.participant_code_version + 1
         )}

      Regex.match?(~r/^\d{6}$/, normalized) ->
        {:ok,
         Ecto.Changeset.change(instance,
           participant_code_digest: hash_code(normalized),
           participant_code_version: instance.participant_code_version + 1
         )}

      true ->
        {:error, :invalid_code}
    end
  end

  defp configured_management_code do
    :wake_canvas
    |> Application.get_env(:management_code, "")
    |> to_string()
    |> String.trim()
  end

  defp hash_code(code) do
    salt = :crypto.strong_rand_bytes(16)
    digest = :crypto.pbkdf2_hmac(:sha256, code, salt, @iterations, 32)
    Base.url_encode64(salt, padding: false) <> "." <> Base.url_encode64(digest, padding: false)
  end

  defp verify_code(encoded, code) do
    with [salt64, digest64] <- String.split(encoded, ".", parts: 2),
         {:ok, salt} <- Base.url_decode64(salt64, padding: false),
         {:ok, expected} <- Base.url_decode64(digest64, padding: false) do
      actual = :crypto.pbkdf2_hmac(:sha256, code, salt, @iterations, 32)
      Plug.Crypto.secure_compare(actual, expected)
    else
      _ -> false
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_left, _right), do: false
end
