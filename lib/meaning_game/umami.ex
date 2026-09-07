defmodule MeaningGame.Umami do
  @moduledoc """
  Umami analytics configuration and boot checks (ticket 11: Umami counts the door).
  """

  require Logger

  @doc """
  Returns the configured Umami script URL and website ID if both are present, or nil.
  """
  @spec config() :: %{script_url: String.t(), website_id: String.t()} | nil
  def config do
    cfg = Application.get_env(:meaning_game, :umami, [])
    url = Keyword.get(cfg, :script_url)
    website_id = Keyword.get(cfg, :website_id)

    if is_binary(url) and url != "" and is_binary(website_id) and website_id != "" do
      %{script_url: url, website_id: website_id}
    else
      nil
    end
  end

  @doc """
  Logs warnings for missing Umami configuration keys, in the same words as bin/deploy.
  """
  @spec warn_missing_keys() :: :ok
  def warn_missing_keys do
    cfg = Application.get_env(:meaning_game, :umami, [])
    url = Keyword.get(cfg, :script_url)
    website_id = Keyword.get(cfg, :website_id)

    has_url = is_binary(url) and url != ""
    has_id = is_binary(website_id) and website_id != ""

    cond do
      has_url and has_id ->
        :ok

      not has_url and not has_id ->
        Logger.warning("no UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID — Umami will count nothing")

      not has_url ->
        Logger.warning("no UMAMI_SCRIPT_URL — Umami will count nothing")

      not has_id ->
        Logger.warning("no UMAMI_WEBSITE_ID — Umami will count nothing")
    end
  end

  @doc """
  Logs missing key warnings at boot unless boot_warnings is disabled.
  """
  @spec warn_at_boot() :: :ok
  def warn_at_boot do
    if Application.get_env(:meaning_game, :boot_warnings, true) do
      warn_missing_keys()
    else
      :ok
    end
  end
end
