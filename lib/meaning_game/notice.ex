defmodule MeaningGame.Notice do
  @moduledoc """
  Delivers a plain-text email notice when a Room is created by a device
  with no history.
  """

  use MeaningGameWeb, :verified_routes

  import Swoosh.Email
  require Logger

  @required_credential_names ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY NOTICE_TO NOTICE_FROM)

  @doc """
  Builds a plain-text notice email carrying the Code, player count, time, and room link.
  """
  def build_email(code, player_count, time \\ DateTime.utc_now()) do
    to_addr = to_address()
    from_addr = from_address()
    link = room_url(code)
    formatted_time = DateTime.to_iso8601(time)

    new()
    |> to(to_addr)
    |> from(from_addr)
    |> subject("Room created: #{code}")
    |> text_body("""
    Room: #{code}
    Players: #{player_count}
    Time: #{formatted_time}
    Link: #{link}
    """)
  end

  @doc """
  Delivers the notice email via MeaningGame.Mailer.
  """
  def deliver(code, player_count, time \\ DateTime.utc_now()) do
    email = build_email(code, player_count, time)
    MeaningGame.Mailer.deliver(email)
  end

  @doc """
  Delivers the notice asynchronously in a supervised task when configured.
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
  True when notice delivery and mailer credentials are configured.
  """
  def configured? do
    notice_config = Application.get_env(:meaning_game, :notice, [])
    to = Keyword.get(notice_config, :to)
    from = Keyword.get(notice_config, :from)

    addresses_configured? = is_binary(to) and to != "" and is_binary(from) and from != ""

    mailer_config = Application.get_env(:meaning_game, MeaningGame.Mailer, [])
    adapter = Keyword.get(mailer_config, :adapter)

    mailer_ready? =
      case adapter do
        Swoosh.Adapters.AmazonSES ->
          Keyword.get(mailer_config, :access_key) not in [nil, ""] and
            Keyword.get(mailer_config, :secret) not in [nil, ""]

        nil ->
          false

        _ ->
          true
      end

    addresses_configured? and mailer_ready?
  end

  @doc """
  Returns a list of missing credential names from the given env map or :system.
  """
  def missing_credentials(env \\ :system) do
    lookup =
      case env do
        :system -> &System.get_env/1
        map when is_map(map) -> &Map.get(map, &1)
      end

    Enum.filter(@required_credential_names, fn name ->
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
    Application.get_env(:meaning_game, :notice, [])[:to]
  end

  defp from_address do
    Application.get_env(:meaning_game, :notice, [])[:from]
  end
end
