defmodule MeaningGame.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    if Application.get_env(:meaning_game, :boot_warnings, true) do
      warn_missing_keys()
    end

    children = [
      MeaningGameWeb.Telemetry,
      MeaningGame.Repo,
      {DNSCluster, query: Application.get_env(:meaning_game, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MeaningGame.PubSub},
      MeaningGameWeb.Presence,
      # A Room is one supervised process, found by its slug. Rooms are started on
      # demand rather than listed here, because which Rooms exist is a question
      # for Postgres and for whoever just opened a URL.
      {Registry, keys: :unique, name: MeaningGame.Rooms.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: MeaningGame.Rooms.Supervisor},
      # Every call to a model runs in a task of its own, so that an Assayer that
      # is slow, or that dies, is something the Room waits on rather than
      # something that happens to it.
      {Task.Supervisor, name: MeaningGame.Steward.Tasks},
      # The Scribe writes under its own supervisor rather than the Steward's,
      # because its work is a different length of thing: an assay lives and dies
      # inside a reveal beat, and a recap is a model writing a paragraph after
      # everyone has stood up. Nothing should have to wait on one to know about
      # the other.
      {Task.Supervisor, name: MeaningGame.Scribe.Tasks},
      # Notice tasks run under their own supervisor so room creation never
      # blocks or fails on mail delivery.
      {Task.Supervisor, name: MeaningGame.Notice.Tasks},
      MeaningGame.Rooms.RateLimit,
      # Start to serve requests, typically the last entry
      MeaningGameWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MeaningGame.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        MeaningGame.Notice.warn_at_boot()
        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MeaningGameWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @doc """
  Logs warnings at boot for missing configuration keys.
  """
  def warn_missing_keys do
    config = Application.get_env(:meaning_game, :umami, [])
    url = Keyword.get(config, :script_url)
    website_id = Keyword.get(config, :website_id)

    has_url = is_binary(url) and url != ""
    has_id = is_binary(website_id) and website_id != ""

    cond do
      has_url and has_id ->
        :ok

      not has_url and not has_id ->
        Logger.warning(
          "UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID are not set; page views will not be counted"
        )

      not has_url ->
        Logger.warning("UMAMI_SCRIPT_URL is not set; page views will not be counted")

      not has_id ->
        Logger.warning("UMAMI_WEBSITE_ID is not set; page views will not be counted")
    end
  end
end
