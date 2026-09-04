defmodule MeaningGameWeb.Router do
  use MeaningGameWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MeaningGameWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MeaningGameWeb.DeviceToken
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MeaningGameWeb do
    pipe_through :browser

    # The bare URL is the couch's Room, because it is the one a player types on a
    # phone. `/r/:slug` is the same view for any other Room, and is what the
    # tests use so each one gets a Room of its own.
    live "/", RoomLive, :default_room
    live "/stage", StageLive, :default_stage
    live "/r/:slug", RoomLive, :room
    live "/r/:slug/stage", StageLive, :stage

    live "/chronicle", ChronicleLive, :default_room
    live "/book", ChronicleLive, :default_room
    live "/r/:slug/chronicle", ChronicleLive, :room
    live "/r/:slug/book", ChronicleLive, :room

    get "/chronicle.md", ChronicleController, :export
    get "/r/:slug/chronicle.md", ChronicleController, :export

    live "/check", CheckLive, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", MeaningGameWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:meaning_game, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MeaningGameWeb.Telemetry
    end
  end
end
