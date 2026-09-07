defmodule MeaningGame.Steward.Title do
  @moduledoc """
  What the Scribe is asked when titling an instrumental Track, and what counts as an answer.

  One system prompt, one JSON schema, one deterministic gate: one to five words,
  letters, digits, spaces, hyphens and apostrophes, at most 40 characters, no quotes.
  An answer that fails is asked for once more with the reason, then falls back to
  the deterministic fallback built from the Gives.
  """

  @version "title-1"

  @system """
  You are the Scribe for Thereish, titling an instrumental music track.

  Write a title of at most five words for an instrumental written from these settings (Gives).
  Rules you do not break:
  - At most five words.
  - At most 40 characters.
  - Letters, digits, spaces, hyphens and apostrophes only.
  - No quotes.
  - No "song".
  """

  @doc "The version of the titling prompt and schema."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  The prompt for titling a Track from player Gives.
  """
  @spec prompt([String.t() | map()]) :: map()
  def prompt(gives) when is_list(gives) do
    theme =
      gives
      |> Enum.map(&MeaningGame.Steward.Author.give_text/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(", ")

    user =
      """
      Settings (Gives): #{theme}

      Write a title of at most five words for an instrumental track written from these settings, no quotes, no "song".
      """
      |> String.trim()

    %{
      system: @system,
      user: user,
      schema: schema(),
      schema_name: "track_title"
    }
  end

  @doc """
  The JSON schema for a title answer.
  """
  @spec schema() :: Jason.OrderedObject.t()
  def schema do
    %Jason.OrderedObject{
      values: [
        {"type", "object"},
        {"properties",
         %Jason.OrderedObject{
           values: [
             {"title",
              %Jason.OrderedObject{
                values: [
                  {"type", "string"},
                  {"description",
                   "A title of at most five words for an instrumental track written from these settings, no quotes, no \"song\"."}
                ]
              }}
           ]
         }},
        {"required", ["title"]},
        {"additionalProperties", false}
      ]
    }
  end

  @doc """
  Extracts the title from the model's decoded JSON answer or raw string.
  """
  @spec title(map() | String.t()) :: String.t() | nil
  def title(json) when is_map(json) do
    case json["title"] || json[:title] do
      t when is_binary(t) -> String.trim(t)
      _ -> nil
    end
  end

  def title(t) when is_binary(t), do: String.trim(t)
  def title(_), do: nil

  @doc """
  Deterministic gate for a proposed Track title.

  Checks that the title has:
  - 1 to 5 words
  - Letters, digits, spaces, hyphens, and apostrophes only
  - At most 40 characters
  - No quotes
  """
  @spec check(map() | String.t()) :: :ok | {:error, String.t()}
  def check(input) do
    case title(input) do
      nil ->
        {:error, "the answer did not contain a title"}

      t ->
        words = String.split(t, ~r/\s+/, trim: true)

        has_quotes? =
          String.contains?(t, ["\"", "“", "”"]) or
            (String.starts_with?(t, "'") and String.ends_with?(t, "'")) or
            (String.starts_with?(t, "‘") and String.ends_with?(t, "’"))

        cond do
          has_quotes? ->
            {:error, "title contains quotes"}

          String.length(t) > 40 ->
            {:error, "title exceeds 40 characters"}

          length(words) < 1 ->
            {:error, "title must be at least 1 word"}

          length(words) > 5 ->
            {:error, "title must be at most 5 words"}

          not Regex.match?(~r/^[\p{L}\p{N}\s'’\-]+$/u, t) ->
            {:error, "title contains invalid characters"}

          true ->
            :ok
        end
    end
  end

  @doc """
  Deterministic fallback title constructed from Gives.

  The Gives, trimmed, title-cased, joined with " · ", cut at 40 characters.
  """
  @spec fallback([String.t() | map()]) :: String.t()
  def fallback(gives) when is_list(gives) do
    gives
    |> Enum.map(&MeaningGame.Steward.Author.give_text/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&title_case/1)
    |> Enum.join(" · ")
    |> String.slice(0, 40)
  end

  defp title_case(str) when is_binary(str) do
    str
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
