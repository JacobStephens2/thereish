defmodule Thereish.Steward.Author do
  @moduledoc """
  The Author role: writes a Page live from the Seats' Gives.

  Takes Gives with player names in roster order, plus a digest of the Room's
  Chronicle when available, and answers two Bookends and a sentence of why.
  Prompt version: author-3.
  """

  alias Thereish.Steward.Legality

  @version "author-3"

  def version, do: @version

  @doc "The JSON schema the Author's responses must satisfy."
  def schema do
    ordered_object([
      {"type", "object"},
      {"properties",
       ordered_object([
         {"bookends",
          ordered_object([
            {"type", "array"},
            {"items", ordered_object([{"type", "string"}])},
            {"description",
             "Exactly two words or two-word phrases, each drawn from a different setting when there are two or more."}
          ])},
         {"why",
          ordered_object([
            {"type", "string"},
            {"description",
             "One sentence explaining why these bookends stand far apart in meaning while each belongs to its setting's world."}
          ])}
       ])},
      {"required", ["bookends", "why"]},
      {"additionalProperties", false}
    ])
  end

  defp ordered_object(values), do: %Jason.OrderedObject{values: values}

  @doc "Validates the Author JSON against the schema with JSV."
  def check_schema(json) do
    case JSV.validate(json, validator()) do
      {:ok, _} ->
        :ok

      {:error, err} ->
        {:error,
         "schema: " <> (err |> JSV.normalize_error() |> Jason.encode!() |> String.slice(0, 600))}
    end
  end

  defp validator do
    key = {__MODULE__, :schema_validator_author_3}

    case :persistent_term.get(key, nil) do
      nil ->
        v = schema() |> to_map() |> JSV.build!()
        :persistent_term.put(key, v)
        v

      v ->
        v
    end
  end

  defp to_map(%Jason.OrderedObject{values: values}),
    do: Map.new(values, fn {key, value} -> {key, to_map(value)} end)

  defp to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  defp to_map(other), do: other

  @doc """
  Deterministic gate: checks schema, exactly two bookends, each 1 or 2 words of
  letters/hyphens/apostrophes, at most 20 chars, distinct roots between them,
  and no word sharing a root with any word of any Give.
  """
  def check(json, gives \\ []) do
    with :ok <- check_schema(json),
         :ok <- check_why(json["why"]),
         :ok <- check_bookends(json["bookends"], gives) do
      :ok
    end
  end

  defp check_why(why) when is_binary(why) do
    if String.trim(why) != "", do: :ok, else: {:error, "why must be non-empty"}
  end

  defp check_why(_), do: {:error, "why must be a string"}

  defp check_bookends([a, b], gives) when is_binary(a) and is_binary(b) do
    with {:ok, words_a} <- validate_bookend(a),
         {:ok, words_b} <- validate_bookend(b),
         :ok <- check_distinct_roots(a, words_a, b, words_b),
         :ok <- check_no_root_with_gives(words_a ++ words_b, gives) do
      :ok
    end
  end

  defp check_bookends(_, _gives) do
    {:error, "bookends must be a list of exactly two items"}
  end

  defp validate_bookend(bookend) do
    trimmed = String.trim(bookend)

    cond do
      String.length(trimmed) > 20 ->
        {:error, "bookend \"#{bookend}\" exceeds 20 characters"}

      trimmed == "" ->
        {:error, "bookend must not be blank"}

      true ->
        words = String.split(trimmed, ~r/\s+/, trim: true)

        cond do
          length(words) not in [1, 2] ->
            {:error, "bookend \"#{bookend}\" must be one or two words"}

          not Enum.all?(words, &Regex.match?(~r/^[A-Za-z'-]+$/, &1)) ->
            {:error, "bookend \"#{bookend}\" must contain letters, hyphens or apostrophes only"}

          true ->
            {:ok, words}
        end
    end
  end

  defp check_distinct_roots(a, words_a, b, words_b) do
    collision =
      Enum.find_value(words_a, fn wa ->
        Enum.find(words_b, fn wb ->
          Legality.shared_root?(wa, wb)
        end)
      end)

    if collision do
      {:error, "bookends \"#{a}\" and \"#{b}\" share a root"}
    else
      :ok
    end
  end

  @doc "Extracts text from a Give."
  def give_text(%{text: text}) when is_binary(text), do: text
  def give_text(%{"text" => text}) when is_binary(text), do: text
  def give_text(%{give: text}) when is_binary(text), do: text
  def give_text(%{"give" => text}) when is_binary(text), do: text
  def give_text(text) when is_binary(text), do: text
  def give_text(_), do: ""

  @doc "Extracts seat name from a Give."
  def give_name(%{name: name}) when is_binary(name), do: name
  def give_name(%{"name" => name}) when is_binary(name), do: name
  def give_name(%{seat_name: name}) when is_binary(name), do: name
  def give_name(%{"seat_name" => name}) when is_binary(name), do: name
  def give_name(_), do: "Seat"

  defp check_no_root_with_gives(bookend_words, gives) do
    give_words =
      gives
      |> Enum.flat_map(fn g -> g |> give_text() |> extract_words() end)

    collision =
      Enum.find_value(bookend_words, fn bw ->
        Enum.find_value(give_words, fn gw ->
          if Legality.shared_root?(bw, gw) do
            {bw, gw}
          end
        end)
      end)

    case collision do
      {bw, gw} ->
        {:error, "bookend word \"#{bw}\" shares a root with setting word \"#{gw}\""}

      nil ->
        :ok
    end
  end

  defp extract_words(text) do
    Regex.scan(~r/[A-Za-z'-]+/, text || "")
    |> List.flatten()
  end

  @system_prompt """
  You are the Author for Thereish, a couch word game.

  Your job:
  Given settings provided by the seats in the Room, write two Bookends:
  1. Exactly two Bookends, each a common English word or two-word phrase (letters, hyphens, apostrophes only, at most 20 characters).
  2. When there are two or more settings, each Bookend MUST be drawn from a DIFFERENT setting.
  3. The two Bookends must stand as far apart in meaning as the settings allow, while each still belongs to its setting's world.
  4. The two Bookends must NOT share a root with each other.
  5. Neither Bookend may use or share a root with any word from any setting.
  6. Provide one sentence explaining why these Bookends stand far apart in meaning while honoring the settings.
  """

  @doc "Builds the request prompt for the Author."
  def prompt(gives, digest \\ nil) do
    gives_list =
      cond do
        is_list(gives) -> gives
        is_map(gives) and is_list(gives[:gives]) -> gives[:gives]
        true -> []
      end

    settings_text =
      if gives_list == [] do
        "Settings: None provided."
      else
        "Settings:\n" <>
          Enum.map_join(gives_list, "\n", fn g ->
            "- #{give_name(g)}: #{give_text(g)}"
          end)
      end

    digest_text =
      if digest && String.trim(digest) != "" do
        "\n\nChronicle digest:\n#{digest}"
      else
        "\n\nChronicle digest:\nNothing yet; this is the first Page."
      end

    user = settings_text <> digest_text

    %{
      role: :author,
      system: @system_prompt,
      user: user,
      schema: schema(),
      schema_name: "authored_page"
    }
  end
end
