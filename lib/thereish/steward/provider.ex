defmodule Thereish.Steward.Provider do
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

  @doc "Answers one question. Every language provider implements it."
  @callback complete(request()) :: {:ok, response()} | {:error, term()}

  @doc """
  The credentials a media provider is called with, each field paired with the
  environment variable that supplies it: `[api_key: "RECRAFT_AI_API_KEY"]`.

  Every media provider declares it, and `Thereish.Steward.provider/3` resolves
  them, so the provider itself reads no configuration.
  """
  @callback credentials() :: [{atom(), String.t()}]

  @optional_callbacks complete: 1, credentials: 0

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

  @doc """
  What an image cost, in dollars (Limner vendors).

  Flat per-image prices are `{:image, dollars}`. Per-megapixel prices are
  `{:megapixel, dollars}` and billed on `width * height / 1_000_000`.
  """
  @spec image_cost(String.t(), pos_integer(), pos_integer()) :: float()
  def image_cost(model, width \\ 512, height \\ 512) do
    case Map.get(prices(), model) do
      {:image, price} ->
        price

      {:megapixel, per_mp} ->
        megapixels = width * height / 1_000_000
        megapixels * per_mp

      _ ->
        0.0
    end
  end

  @doc """
  Downloads bytes from a URL, using the same HTTP options the providers share.
  """
  @spec get_bytes(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get_bytes(url, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    provider = Keyword.get(opts, :provider)

    req_opts =
      [
        url: url,
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(http_options(provider))

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:download_failed, {:http, status, decode_body(body)}}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  @doc """
  True when a vendor response is a content refusal rather than a transport error.
  """
  @spec refused?(term(), term()) :: boolean()
  def refused?(status, body) when is_integer(status) do
    status in [400, 403, 422, 451] and moderation_message?(body)
  end

  def refused?(status, _body) when is_binary(status) do
    String.downcase(status) in [
      "request moderated",
      "content moderated",
      "moderated"
    ]
  end

  def refused?(_, _), do: false

  defp moderation_message?(body) do
    text = body |> inspect() |> String.downcase()

    Enum.any?(
      [
        "moderat",
        "safety",
        "nsfw",
        "content policy",
        "content_policy",
        "refused",
        "not allowed",
        "prohibited",
        "blocked"
      ],
      &String.contains?(text, &1)
    )
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
    :thereish |> Application.fetch_env!(:steward) |> Keyword.get(key, default)
  end
end
