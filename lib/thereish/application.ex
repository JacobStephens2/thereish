defmodule Thereish.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Thereish.Steward.warn_missing_foley_keys()
    Thereish.Umami.warn_at_boot()

    children = [
      ThereishWeb.Telemetry,
      Thereish.Repo,
      {DNSCluster, query: Application.get_env(:thereish, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Thereish.PubSub},
      ThereishWeb.Presence,
      # A Room is one supervised process, found by its slug. Rooms are started on
      # demand rather than listed here, because which Rooms exist is a question
      # for Postgres and for whoever just opened a URL.
      {Registry, keys: :unique, name: Thereish.Rooms.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Thereish.Rooms.Supervisor},
      # Every call to a model runs in a task of its own, so that an Assayer that
      # is slow, or that dies, is something the Room waits on rather than
      # something that happens to it.
      {Task.Supervisor, name: Thereish.Steward.Tasks},
      # The Scribe writes under its own supervisor rather than the Steward's,
      # because its work is a different length of thing: an assay lives and dies
      # inside a reveal beat, and a recap is a model writing a paragraph after
      # everyone has stood up. Nothing should have to wait on one to know about
      # the other.
      {Task.Supervisor, name: Thereish.Scribe.Tasks},
      # Notice tasks run under their own supervisor so room creation never
      # blocks or fails on mail delivery.
      {Task.Supervisor, name: Thereish.Notice.Tasks},
      Thereish.Rooms.RateLimit,
      # Start to serve requests, typically the last entry
      ThereishWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Thereish.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Thereish.Notice.warn_at_boot()
        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThereishWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @doc """
  Logs warnings at boot for missing configuration keys.
  """
  defdelegate warn_missing_keys, to: Thereish.Umami
end
