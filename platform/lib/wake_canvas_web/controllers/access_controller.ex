defmodule WakeCanvasWeb.AccessController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Access
  alias WakeCanvas.Access.AttemptLimiter
  alias WakeCanvas.Experiences

  def management_form(conn, params) do
    if Access.management_authorized?(conn) do
      redirect(conn, to: safe_return_to(params["return_to"], "/manage"))
    else
      render_code_form(conn, %{
        title: "WakeCanvas management",
        message: "Enter the six-digit management code.",
        action: ~p"/access/manage",
        return_to: safe_return_to(params["return_to"], "/manage"),
        error: nil
      })
    end
  end

  def management_login(conn, params) do
    return_to = safe_return_to(params["return_to"], "/manage")
    attempt_key = {:management, conn.remote_ip}

    case AttemptLimiter.check(attempt_key) do
      :ok ->
        if Access.verify_management_code(params["code"]) do
          AttemptLimiter.success(attempt_key)
          conn |> Access.authorize_management() |> redirect(to: return_to)
        else
          AttemptLimiter.failure(attempt_key)

          conn
          |> put_status(:unauthorized)
          |> render_code_form(%{
            title: "WakeCanvas management",
            message: "Enter the six-digit management code.",
            action: ~p"/access/manage",
            return_to: return_to,
            error: "That code was not accepted."
          })
        end

      {:error, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> render_code_form(%{
          title: "WakeCanvas management",
          message: "Enter the six-digit management code.",
          action: ~p"/access/manage",
          return_to: return_to,
          error: "Too many attempts. Wait about #{retry_after} seconds and try again."
        })
    end
  end

  def management_logout(conn, _params) do
    conn |> Access.clear_management() |> redirect(to: ~p"/access/manage")
  end

  def participant_form(conn, %{"instance_id" => reference} = params) do
    with instance when not is_nil(instance) <- Experiences.get_instance(reference) do
      return_to = safe_return_to(params["return_to"], "/i/#{instance.id}/artwork")

      if Access.participant_authorized?(conn, instance) do
        redirect(conn, to: return_to)
      else
        render_code_form(conn, %{
          title: instance.name,
          message: "Enter this workshop's six-digit participant code.",
          action: "/access/instances/#{instance.id}",
          return_to: return_to,
          error: nil
        })
      end
    else
      _ -> send_resp(conn, :not_found, "Experience instance not found")
    end
  end

  def participant_login(conn, %{"instance_id" => reference} = params) do
    with instance when not is_nil(instance) <- Experiences.get_instance(reference) do
      return_to = safe_return_to(params["return_to"], "/i/#{instance.id}/artwork")
      attempt_key = {:participant, instance.id, conn.remote_ip}

      case AttemptLimiter.check(attempt_key) do
        :ok ->
          if Access.valid_participant_code?(instance, params["code"]) do
            AttemptLimiter.success(attempt_key)
            conn |> Access.authorize_participant(instance) |> redirect(to: return_to)
          else
            AttemptLimiter.failure(attempt_key)

            conn
            |> put_status(:unauthorized)
            |> render_code_form(%{
              title: instance.name,
              message: "Enter this workshop's six-digit participant code.",
              action: "/access/instances/#{instance.id}",
              return_to: return_to,
              error: "That code was not accepted."
            })
          end

        {:error, retry_after} ->
          conn
          |> put_resp_header("retry-after", Integer.to_string(retry_after))
          |> put_status(:too_many_requests)
          |> render_code_form(%{
            title: instance.name,
            message: "Enter this workshop's six-digit participant code.",
            action: "/access/instances/#{instance.id}",
            return_to: return_to,
            error: "Too many attempts. Wait about #{retry_after} seconds and try again."
          })
      end
    else
      _ -> send_resp(conn, :not_found, "Experience instance not found")
    end
  end

  defp render_code_form(conn, assigns) do
    escaped_title = assigns.title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    escaped_message =
      assigns.message |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    escaped_action = assigns.action |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    escaped_return =
      assigns.return_to |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    csrf = Plug.CSRFProtection.get_csrf_token()

    error =
      if assigns.error do
        escaped = assigns.error |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        ~s(<p class="alert alert-error">#{escaped}</p>)
      else
        ""
      end

    html(
      conn,
      """
      <!doctype html>
      <html lang="en">
      <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>#{escaped_title}</title></head>
      <body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#f3efe7;color:#29251f;font-family:ui-sans-serif,system-ui;padding:1rem">
        <main style="width:min(100%,28rem);background:white;border-radius:1.5rem;padding:2rem;box-shadow:0 24px 70px #4b382325">
          <p style="margin:0;color:#8b5e3c;font-size:.75rem;font-weight:700;letter-spacing:.16em;text-transform:uppercase">WakeCanvas</p>
          <h1 style="margin:.6rem 0;font:500 2rem/1.1 Georgia,serif">#{escaped_title}</h1>
          <p style="color:#6c6255;line-height:1.5">#{escaped_message}</p>
          #{error}
          <form method="post" action="#{escaped_action}" style="display:grid;gap:1rem;margin-top:1.5rem">
            <input type="hidden" name="_csrf_token" value="#{csrf}">
            <input type="hidden" name="return_to" value="#{escaped_return}">
            <input name="code" type="password" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" autofocus required aria-label="Six-digit access code" style="font:700 1.6rem/1 ui-monospace,monospace;letter-spacing:.3em;text-align:center;padding:1rem;border:1px solid #c8bba9;border-radius:.8rem">
            <button style="border:0;border-radius:.8rem;padding:1rem;background:#2d5d50;color:white;font-weight:700;font-size:1rem;cursor:pointer">Continue</button>
          </form>
        </main>
      </body>
      </html>
      """
    )
  end

  defp safe_return_to(path, fallback) when is_binary(path) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//"),
      do: path,
      else: fallback
  end

  defp safe_return_to(_path, fallback), do: fallback
end
