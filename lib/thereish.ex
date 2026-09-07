defmodule Thereish do
  @moduledoc """
  Thereish keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Returns the configured Umami script URL and website ID if both are present, or nil.
  """
  defdelegate umami_config, to: Thereish.Umami, as: :config
end
