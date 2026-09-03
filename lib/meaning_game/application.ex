defmodule MeaningGame.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MeaningGameWeb.Telemetry,
      MeaningGame.Repo,
      {DNSCluster, query: Application.get_env(:meaning_game, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MeaningGame.PubSub},
      # A Room is one supervised process, found by its slug. Rooms are started on
      # demand rather than listed here, because which Rooms exist is a question
      # for Postgres and for whoever just opened a URL.
      {Registry, keys: :unique, name: MeaningGame.Rooms.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: MeaningGame.Rooms.Supervisor},
      # Start to serve requests, typically the last entry
      MeaningGameWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MeaningGame.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MeaningGameWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
