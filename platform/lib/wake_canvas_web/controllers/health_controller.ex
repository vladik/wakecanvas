defmodule WakeCanvasWeb.HealthController do
  use WakeCanvasWeb, :controller

  alias WakeCanvas.Diagnostics

  def show(conn, _params) do
    report = Diagnostics.public_snapshot()
    status = if report.status == :error, do: :service_unavailable, else: :ok

    conn
    |> put_status(status)
    |> json(report)
  end
end
