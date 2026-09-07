defmodule MeaningGame.Steward.Naming do
  @moduledoc """
  What the Scribe is asked when naming a Room, and what counts as an answer.

  One system prompt, one JSON schema, one deterministic gate: four letters, in
  the dictionary, free of profanity, and not already taken by an existing Room.
  An answer that fails is asked for once more (design law 14), with the rule
  quoted back.
  """

  alias MeaningGame.Steward.Legality

  @version "naming-1"

  @system """
  You are the Scribe for Thereish, naming a new Room.

  When players who have played before create a Room, its Code nods to that history — a couple that melded on candy cane might be handed CANE tonight.
  Along with the Code, write a quip: one line of at most 90 characters about the Code, in the Assayer's register and the Scribe's voice, naming no player because none exists yet.

  Given the digests of past Rooms played and the list of already taken Codes, choose exactly one four-letter English word as the new Room's Code, and a quip about the Code.

  Rules you do not break:
  - Exactly one English word of four letters (A-Z).
  - Must be a real dictionary word.
  - Never profane or inappropriate.
  - Must not be one of the already taken Codes.
  - The word should subtly nod to the themes, gives, bookends, or bridges in the history.
  - The quip must be a single line of at most 90 characters about the Code, in the Assayer's register and Scribe's voice, naming no player.
  """

  @doc "The version of the naming prompt and schema."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  The prompt for naming a Room from history and avoiding taken codes.
  """
  @spec prompt([String.t()], [String.t()]) :: map()
  def prompt(digests, taken_codes) do
    user =
      """
      Past Room history:

      #{Enum.join(digests, "\n\n---\n\n")}

      Codes already taken (do not use any of these):
      #{Enum.join(taken_codes, ", ")}

      Choose one four-letter word that nods to the history and is not taken, and a quip about the Code.
      """
      |> String.trim()

    %{
      system: @system,
      user: user,
      schema: schema(),
      schema_name: "room_code"
    }
  end

  @quip_system """
  You are the Scribe for Thereish, writing a quip for a new Room.

  Given the Room's four-letter Code, write exactly one line of at most 90 characters about the Code, in the Assayer's register and the Scribe's voice.
  Name no player because none exists yet.
  """

  @doc """
  The prompt for writing a quip for a given Room Code.
  """
  @spec quip_prompt(String.t()) :: map()
  def quip_prompt(word) do
    user =
      """
      Room Code: #{String.upcase(word)}

      Write one line of at most 90 characters about this Code.
      """
      |> String.trim()

    %{
      system: @quip_system,
      user: user,
      schema: quip_schema(),
      schema_name: "room_quip"
    }
  end

  @doc """
  The JSON schema for a quip-only answer.
  """
  @spec quip_schema() :: Jason.OrderedObject.t()
  def quip_schema do
    %Jason.OrderedObject{
      values: [
        {"type", "object"},
        {"properties",
         %Jason.OrderedObject{
           values: [
             {"quip",
              %Jason.OrderedObject{
                values: [
                  {"type", "string"},
                  {"description", "One line of at most 90 characters about the Code."}
                ]
              }}
           ]
         }},
        {"required", ["quip"]},
        {"additionalProperties", false}
      ]
    }
  end

  @doc """
  The JSON schema for a room code answer.
  """
  @spec schema() :: Jason.OrderedObject.t()
  def schema do
    %Jason.OrderedObject{
      values: [
        {"type", "object"},
        {"properties",
         %Jason.OrderedObject{
           values: [
             {"word",
              %Jason.OrderedObject{
                values: [
                  {"type", "string"},
                  {"description", "One real four-letter English word nodding to the history."}
                ]
              }},
             {"quip",
              %Jason.OrderedObject{
                values: [
                  {"type", "string"},
                  {"description",
                   "One line of at most 90 characters about the Code, in the Assayer's register and Scribe's voice."}
                ]
              }}
           ]
         }},
        {"required", ["word"]},
        {"additionalProperties", false}
      ]
    }
  end

  @doc """
  Extracts and normalises the word from the model's decoded JSON answer.
  """
  @spec word(map()) :: String.t() | nil
  def word(json) when is_map(json) do
    case json["word"] || json[:word] do
      w when is_binary(w) -> w |> String.trim() |> String.downcase()
      _ -> nil
    end
  end

  @doc """
  Extracts and validates the quip from the model's decoded JSON answer.

  Returns a trimmed single-line string of at most 90 characters, or nil if invalid.
  """
  @spec quip(map()) :: String.t() | nil
  def quip(json) when is_map(json) do
    case json["quip"] || json[:quip] do
      q when is_binary(q) ->
        trimmed = String.trim(q)

        if trimmed != "" and String.length(trimmed) <= 90 and
             not String.contains?(trimmed, ["\r", "\n"]) do
          trimmed
        else
          nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Deterministic gate for the Scribe's proposed word.

  Checks that the word is 4 letters, in the ENABLE dictionary, not profane, and
  not an existing Code.
  """
  @spec check(map(), [String.t()]) :: :ok | {:error, String.t()}
  def check(json, taken_codes) do
    case word(json) do
      nil ->
        {:error, "the answer did not contain a word"}

      w ->
        taken = MapSet.new(taken_codes, &String.downcase/1)

        cond do
          String.length(w) != 4 ->
            {:error, "\"#{w}\" is not a four-letter word."}

          not Legality.in_dictionary?(w) ->
            {:error, "\"#{w}\" is not in the dictionary."}

          Legality.profane?(w) ->
            {:error, "\"#{w}\" is profane."}

          MapSet.member?(taken, w) ->
            {:error, "\"#{w}\" is already a Code."}

          true ->
            :ok
        end
    end
  end
end
