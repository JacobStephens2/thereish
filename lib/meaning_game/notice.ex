defmodule MeaningGame.Notice do
  @moduledoc """
  Delivers a plain-text email notice when a Room is created by a device
  with no history.
  """

  use MeaningGameWeb, :verified_routes

  import Swoosh.Email
  require Logger

  @credential_names ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION NOTICE_TO NOTICE_FROM)

  @doc """
  Builds a plain-text notice email carrying the Code, player count, time, and room link.
  """
  def build_email(code, player_count, time \\ DateTime.utc_now()) do
    to_address = to_address()
    from_address = from_address()
    link = room_url(code)
    formatted_time = DateTime.to_iso8601(time)

    new()
    |> to(to_address)
    |> from(from_address)
    |> subject("Room created: #{code}")
    |> text_body("""
    Room: #{code}
    Players: #{player_count}
    Time: #{formatted_time}
    Link: #{link}
    """)
  end

  @doc """
  Delivers the notice email via MeaningGame.Mailer if configured.
  """
  def deliver(code, player_count, time \\ DateTime.utc_now()) do
    if configured?() do
      email = build_email(code, player_count, time)
      MeaningGame.Mailer.deliver(email)
    else
      :ok
    end
  end

  @doc """
  Delivers the notice asynchronously in a supervised task.
  Never raises, times out, or blocks the caller.
  """
  def notify_new_room(code, player_count) do
    if configured?() do
      Task.Supervisor.start_child(MeaningGame.Notice.Tasks, fn ->
        try do
          case deliver(code, player_count) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.error("Failed to deliver room notice for #{code}: #{inspect(reason)}")
              :ok
          end
        rescue
          e ->
            Logger.error("Error delivering room notice for #{code}: #{Exception.message(e)}")
            :ok
        catch
          :exit, reason ->
            Logger.error("Exit delivering room notice for #{code}: #{inspect(reason)}")
            :ok
        end
      end)
    else
      :ok
    end
  end

  @doc """
  True when notice delivery is configured.
  """
  def configured? do
    config = Application.get_env(:meaning_game, :notice, [])
    to = Keyword.get(config, :to)
    from = Keyword.get(config, :from)

    configured_addresses? = is_binary(to) and to != "" and is_binary(from) and from != ""

    if Application.get_env(:meaning_game, :env) == :prod or config_env_is_prod?() do
      configured_addresses? and missing_credentials(:system) == []
    else
      configured_addresses?
    end
  end

  @doc """
  Returns a list of missing credential names from the given env map or :system.
  """
  def missing_credentials(env \\ :system) do
    lookup =
      case env do
        :system -> &System.get_env/1
        map when is_map(map) -> &Map.get(map, &1)
        kw when is_list(kw) -> &Keyword.get(kw, String.to_atom(&1))
      end

    Enum.filter(@credential_names, fn name ->
      val = lookup.(name)
      is_nil(val) or val == ""
    end)
  end

  @doc """
  Logs a warning naming missing credential names at boot, or stays silent when all are present.
  """
  def warn_at_boot(env \\ :system) do
    missing = missing_credentials(env)

    if missing != [] do
      Logger.warning("Notice mailer not configured: missing #{Enum.join(missing, ", ")}")
    end

    :ok
  end

  defp room_url(code) do
    url(~p"/r/#{code}")
  end

  defp to_address do
    Application.get_env(:meaning_game, :notice, [])[:to] || "operator@example.com"
  end

  defp from_address do
    Application.get_env(:meaning_game, :notice, [])[:from] || "notice@thereish.app"
  end

  defp config_env_is_prod? do
    System.get_env("RELEASE_NAME") != nil
  end
end
