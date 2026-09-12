defmodule ThereishWeb.Router do
  use ThereishWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThereishWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ThereishWeb.DeviceToken
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ThereishWeb do
    pipe_through :browser

    # The bare URL is the door: a Code to type, a Room to open, a way back into
    # the Rooms this phone is already in. Every Room lives under its Code, the
    # couch included — there is no Room the URL means on its own any more.
    live "/", FrontLive, :front
    live "/new", NewRoomLive, :new

    live "/r/:slug", RoomLive, :room
    live "/r/:slug/stage", StageLive, :stage

    live "/r/:slug/chronicle", ChronicleLive, :room
    live "/r/:slug/book", ChronicleLive, :room

    get "/r/:slug/chronicle.md", ChronicleController, :export
    get "/r/:slug/voice/:attempt", VoiceController, :show
    get "/r/:slug/voice/:attempt/:kind", VoiceController, :show

    # Every Room's calibration at once, which is an operator's export rather
    # than a Room's, and so is the one thing here that names no Code.
    get "/calibration.json", ChronicleController, :export_calibration, assigns: %{format: :json}
    get "/calibration.jsonl", ChronicleController, :export_calibration, assigns: %{format: :jsonl}

    get "/r/:slug/calibration.json", ChronicleController, :export_calibration,
      assigns: %{format: :json}

    get "/r/:slug/calibration.jsonl", ChronicleController, :export_calibration,
      assigns: %{format: :jsonl}

    live "/check", CheckLive, :show

    # Operator spend page across all Rooms by role and model (ticket 09)
    live "/spend", SpendLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", ThereishWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:thereish, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ThereishWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
