defmodule Thereish.Steward.Author do
  @moduledoc """
  The Author role: writes a Page live from the Seats' Gives.

  Takes Gives with player names in roster order, the count of Bookends wanted
  (one per Give at a Full table, or two), plus a digest of the Room's Chronicle
  when available, and answers that many Bookends and a sentence of why.
  Prompt version: author-4.
  """

  alias Thereish.Steward.Legality

  @version "author-4"

  def version, do: @version

  @doc "The count of Bookends a request asked for. Two when the request is silent."
  def requested_count(request) do
    cond do
      is_map(request) and is_integer(request[:count]) -> request[:count]
      is_map(request) and is_integer(request["count"]) -> request["count"]
      true -> 2
    end
  end

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
             "The words or two-word phrases asked for, each drawn from a different setting when there are two or more."}
          ])},
         {"from",
          ordered_object([
            {"type", "array"},
            {"items", ordered_object([{"type", "string"}])},
            {"description",
             "The Seat name heading the setting each Bookend was drawn from, in the same order as bookends. At a Full table this is every setting once."}
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
    key = {__MODULE__, :schema_validator_author_4}

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
  Deterministic gate: checks schema, exactly `count` bookends, each 1 or 2 words
  of letters/hyphens/apostrophes, at most 20 chars, distinct roots across them,
  no word sharing a root with any word of any Give, and at a Full table one
  Bookend from each Give.
  """
  def check(json, gives \\ [], count \\ 2)

  def check(json, gives, count) when is_integer(count) and count >= 1 do
    with :ok <- check_schema(json),
         :ok <- check_why(json["why"]),
         :ok <- check_bookends(json["bookends"], json["from"], gives, count) do
      :ok
    end
  end

  defp check_why(why) when is_binary(why) do
    if String.trim(why) != "", do: :ok, else: {:error, "why must be non-empty"}
  end

  defp check_why(_), do: {:error, "why must be a string"}

  defp check_bookends(bookends, from, gives, count) when is_list(bookends) do
    cond do
      length(bookends) != count or not Enum.all?(bookends, &is_binary/1) ->
        {:error, "bookends must be a list of exactly #{count} items"}

      true ->
        with {:ok, word_lists} <- validate_bookends(bookends),
             :ok <- check_all_distinct_roots(bookends, word_lists),
             :ok <- check_no_root_with_gives(List.flatten(word_lists), gives),
             :ok <- check_from(from, gives, count) do
          :ok
        end
    end
  end

  defp check_bookends(_, _from, _gives, count) do
    {:error, "bookends must be a list of exactly #{count} items"}
  end

  defp validate_bookends(bookends) do
    Enum.reduce_while(bookends, {:ok, []}, fn bookend, {:ok, acc} ->
      case validate_bookend(bookend) do
        {:ok, words} -> {:cont, {:ok, acc ++ [words]}}
        error -> {:halt, error}
      end
    end)
  end

  defp check_all_distinct_roots(bookends, word_lists) do
    pairs =
      for {a, i} <- Enum.with_index(bookends),
          {b, j} <- Enum.with_index(bookends),
          i < j do
        {a, Enum.at(word_lists, i), b, Enum.at(word_lists, j)}
      end

    Enum.reduce_while(pairs, :ok, fn {a, words_a, b, words_b}, :ok ->
      case check_distinct_roots(a, words_a, b, words_b) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_from(_from, gives, _count) when gives == [] or is_nil(gives), do: :ok

  defp check_from(from, gives, count) do
    required? = length(gives) == count and count >= 2
    known = MapSet.new(Enum.map(gives, &(&1 |> give_name() |> normalize_name())))

    cond do
      is_nil(from) and not required? ->
        :ok

      not is_list(from) or length(from) != count or not Enum.all?(from, &is_binary/1) ->
        {:error, "each bookend must name the setting it was drawn from"}

      from |> Enum.map(&normalize_name/1) |> Enum.uniq() |> length() != length(from) ->
        {:error, "two bookends from the same setting"}

      not Enum.all?(from, &(normalize_name(&1) in known)) ->
        {:error, "each bookend must name the setting it was drawn from"}

      true ->
        :ok
    end
  end

  defp normalize_name(name), do: name |> to_string() |> String.trim() |> String.downcase()

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

  @doc "Builds the request prompt for the Author."
  def prompt(gives, digest \\ nil, count \\ 2) do
    gives_list =
      cond do
        is_list(gives) -> gives
        is_map(gives) and is_list(gives[:gives]) -> gives[:gives]
        true -> []
      end

    full_table? = count == length(gives_list) and count >= 2

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
      system: system_prompt(count, full_table?),
      user: user,
      schema: schema(),
      schema_name: "authored_page"
    }
  end

  defp system_prompt(count, full_table?) do
    {rule, from_each, from_line} =
      if full_table? do
        {"This Page is a Full table.",
         "Each Bookend MUST belong to a DIFFERENT setting's world — one Bookend from each setting.",
         "Name the Seat heading each setting in `from`, in the same order as `bookends`. At a Full table this is every setting once."}
      else
        {"This Page is not a Full table.",
         "When there are two or more settings, each Bookend MUST be drawn from a DIFFERENT setting.",
         "Name the Seat heading each setting in `from`, in the same order as `bookends`."}
      end

    """
    You are the Author for Thereish, a couch word game.

    #{rule}

    Your job:
    Given settings provided by the seats in the Room, write Bookends:
    1. Exactly #{count} Bookends, each a common English word or two-word phrase (letters, hyphens, apostrophes only, at most 20 characters).
    2. #{from_each}
    3. The Bookends must stand as far apart from one another in meaning as the settings allow, while each still belongs to its setting's world.
    4. The Bookends must NOT share a root with each other.
    5. No Bookend may use or share a root with any word from any setting.
    6. #{from_line}
    7. Provide one sentence explaining why these Bookends stand far apart in meaning while honoring the settings.
    """
  end
end
