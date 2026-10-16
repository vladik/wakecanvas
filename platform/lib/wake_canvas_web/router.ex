defmodule WakeCanvasWeb.Router do
  use WakeCanvasWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WakeCanvasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WakeCanvasWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/manage", ManageLive
    get "/display", SurfaceController, :active_display
    get "/media/instances/:instance_id/:filename", MediaController, :show
    get "/i/:instance_id/:surface", SurfaceController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", WakeCanvasWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:wake_canvas, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WakeCanvasWeb.Telemetry
    end
  end
end
