defmodule MeaningGame do
  @moduledoc """
  MeaningGame keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Returns the configured Umami script URL and website ID if both are present, or nil.
  """
  def umami_config do
    config = Application.get_env(:meaning_game, :umami, [])
    url = Keyword.get(config, :script_url)
    website_id = Keyword.get(config, :website_id)

    if is_binary(url) and url != "" and is_binary(website_id) and website_id != "" do
      %{script_url: url, website_id: website_id}
    else
      nil
    end
  end
end
