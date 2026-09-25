defmodule ThereishWeb.Router do
  use ThereishWeb, :router

  import ThereishWeb.AdminAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThereishWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug ThereishWeb.DeviceToken
    plug :fetch_current_admin
  end

  pipeline :require_admin do
    plug :require_authenticated_admin
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

    # What Thereish is, for someone nobody has told a Code yet.
    get "/game", GameController, :show

    live "/r/:slug", RoomLive, :room
    live "/r/:slug/stage", StageLive, :stage

    live "/r/:slug/chronicle", ChronicleLive, :room
    live "/r/:slug/book", ChronicleLive, :room

    get "/r/:slug/voice/:attempt", VoiceController, :show
    get "/r/:slug/voice/:attempt/:kind", VoiceController, :show

    live "/check", CheckLive, :show

    live_session :admin_guest, on_mount: [{ThereishWeb.AdminAuth, :redirect_if_admin}] do
      live "/admin/sign-in", AdminSignInLive, :new
      live "/admin/reset-password", AdminResetPasswordLive, :new
      live "/admin/reset-password/:token", AdminResetPasswordLive, :edit
    end

    post "/admin/sign-in", AdminSessionController, :create
    delete "/admin/sign-out", AdminSessionController, :delete
  end

  scope "/", ThereishWeb do
    pipe_through [:browser, :require_admin]

    live_session :admin, on_mount: [{ThereishWeb.AdminAuth, :require_admin}] do
      live "/admin", AdminOverviewLive, :index
      live "/admin/rooms", AdminRoomsLive, :index
      live "/admin/timing", AdminTimingLive, :index
      live "/admin/timing/:slug", AdminTimingLive, :room
      live "/admin/experiments", AdminExperimentsLive, :index
      live "/admin/media", AdminMediaLive, :index
      live "/spend", SpendLive, :index
    end

    get "/r/:slug/chronicle.md", ChronicleController, :export

    get "/calibration.json", ChronicleController, :export_calibration, assigns: %{format: :json}
    get "/calibration.jsonl", ChronicleController, :export_calibration, assigns: %{format: :jsonl}

    get "/r/:slug/calibration.json", ChronicleController, :export_calibration,
      assigns: %{format: :json}

    get "/r/:slug/calibration.jsonl", ChronicleController, :export_calibration,
      assigns: %{format: :jsonl}
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
