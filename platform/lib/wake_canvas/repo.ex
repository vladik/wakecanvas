defmodule WakeCanvas.Repo do
  use Ecto.Repo,
    otp_app: :wake_canvas,
    adapter: Ecto.Adapters.SQLite3
end
