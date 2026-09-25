defmodule ThereishWeb.GameHTML do
  use ThereishWeb, :html

  alias Thereish.Ladder

  embed_templates "game_html/*"

  # The rungs as the table reads them, from the configured Ladder, so a
  # calibration change moves this page too.
  def ladder do
    for {band, floor} <- Ladder.bands() do
      {band |> Atom.to_string() |> String.replace("_", " "), floor}
    end
  end
end
