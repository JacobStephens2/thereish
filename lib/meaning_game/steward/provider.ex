defmodule MeaningGame.Steward.Provider do
  @moduledoc """
  The wire: what a provider is asked for and what it hands back.

  This is the innermost layer of the one seam, and the only place in the
  codebase where a company's name appears. Above it the Steward knows about
  roles, orderings, hedging and validation; below it there is an HTTP request to
  somebody's endpoint. Which provider is behind a role is configuration, so
  moving the Assayer from one company to another is a setting rather than a
  refactor (spec, "Operating it").

  A response carries what it cost, because the price list is a fact about the
  provider and every verdict is expected to say what it spent.
  """

  @typedoc "One question for one model, with the knobs that role is configured with."
  @type request :: %{
          system: String.t(),
          user: String.t(),
          schema: Jason.OrderedObject.t(),
          schema_name: String.t(),
          model: String.t(),
          effort: String.t(),
          max_tokens: pos_integer(),
          timeout_ms: pos_integer(),
          api_key: String.t() | nil
        }

  @typedoc """
  One answer. `json` is nil when the model answered with something that was not
  a JSON object at all, which the gate treats as a rejected answer rather than
  as a broken provider.
  """
  @type response :: %{
          json: map() | nil,
          model: String.t(),
          stop_reason: String.t() | nil,
          cost_usd: float()
        }

  @callback complete(request()) :: {:ok, response()} | {:error, term()}

  @doc """
  What a call cost, in dollars, from the tokens the provider reported.

  Prices are configuration rather than constants: they are read off a pricing
  page on a particular day and they move without asking. A model nobody has
  priced costs zero, which is wrong in a way the Chronicle will make obvious,
  and is better than a Page that dies over a missing entry in a price list.
  """
  @spec cost(String.t(), non_neg_integer(), non_neg_integer()) :: float()
  def cost(model, input_tokens, output_tokens) do
    case Map.get(prices(), model, {0.0, 0.0}) do
      {per_input, per_output} ->
        input_tokens / 1.0e6 * per_input + output_tokens / 1.0e6 * per_output

      _ ->
        0.0
    end
  end

  @doc """
  What a call cost, in dollars, from characters consumed (ElevenLabs sound effects / voice).
  """
  @spec character_cost(String.t(), non_neg_integer()) :: float()
  def character_cost(model, characters) when is_number(characters) and characters >= 0 do
    case Map.get(prices(), model) do
      {:characters, per_char} ->
        characters * per_char

      per_char when is_number(per_char) ->
        characters * per_char * 1.0

      _ ->
        0.0
    end
  end

  @doc """
  What a track cost, in dollars (Mureka instrumental music).
  """
  @spec track_cost(String.t()) :: float()
  def track_cost(model) do
    case Map.get(prices(), model) do
      {:track, price} -> price
      _ -> 0.0
    end
  end

  @doc "Decodes JSON body if binary, returning decoded map or original body on failure."
  def decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      _ -> body
    end
  end

  def decode_body(body), do: body

  @doc """
  Options handed to every HTTP request the providers make.

  Empty in the ordinary case. It is how the tests put a recorded response where
  a provider would be, so that the Steward's own tests never call anybody and
  never spend anything.
  """
  @spec http_options(module() | nil) :: keyword()
  def http_options(provider \\ nil) do
    opts = config(:http_options, [])

    case {provider, opts[:plug]} do
      {provider, {Req.Test, _}} when not is_nil(provider) ->
        Keyword.put(opts, :plug, {Req.Test, provider})

      _ ->
        opts
    end
  end

  defp prices, do: config(:prices, %{})

  defp config(key, default) do
    :meaning_game |> Application.fetch_env!(:steward) |> Keyword.get(key, default)
  end
end
