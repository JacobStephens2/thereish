defmodule MeaningGame.Steward.Gemini do
  @moduledoc """
  Google's models, through their OpenAI-compatible endpoint.

  The Assayer is Gemini 3.8 Flash at low effort (ADR-0005), chosen for
  repeatability rather than for speed or for fairness: a constant offset is a
  calibration the couple make once, while an Assayer that answers differently
  every time makes the first grade on a borderline pair a dice roll that the
  cache then freezes as precedent.

  **Not streamed, deliberately.** The Steward prototype streamed in order to
  measure time-to-first-token, which is a bench statistic; the game cannot show
  half a verdict, so what it waits for is the whole answer either way. Asking
  for the whole thing costs the same wall clock and saves an SSE parser, and it
  is why a recorded response in a test is a JSON file rather than a transcript.

  Two details of this endpoint that are not guessable and were confirmed against
  it on 2026-09-02: thinking cannot be turned off on 3.8 Flash, so `low` is the
  floor rather than a preference, and `completion_tokens` excludes the thinking
  while `total_tokens` includes it — so the tokens that get billed as output are
  `total - prompt` rather than the completion count.
  """
  @behaviour MeaningGame.Steward.Provider

  require Logger

  alias MeaningGame.Steward.Provider

  @url "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"

  @impl true
  def complete(request) do
    with {:ok, key} <- api_key(request) do
      [
        json: body(request),
        auth: {:bearer, key},
        receive_timeout: request.timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))
      |> then(&Req.post(@url, &1))
      |> answer()
    end
  end

  # The key is configuration like the model and the effort are, read out of
  # `GEMINI_API_KEY` in `config/runtime.exs` so that nothing has to reach for the
  # environment mid-Page.
  #
  # A missing key is reported rather than raised, because the game already knows
  # what to do with an Assayer that cannot answer, and taking a Room down in
  # front of the couple is not it. It is logged loudly: an evening graded
  # entirely by "no verdict" is a configuration mistake, not a design.
  defp api_key(%{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_request) do
    Logger.error("GEMINI_API_KEY is not set; the Assayer cannot grade anything")

    {:error, :no_api_key}
  end

  defp body(request) do
    %{
      model: request.model,
      messages: [
        %{role: "system", content: request.system},
        %{role: "user", content: request.user}
      ],
      reasoning_effort: request.effort,
      max_tokens: request.max_tokens,
      response_format: %{
        type: "json_schema",
        json_schema: %{name: request.schema_name, strict: true, schema: request.schema}
      }
    }
  end

  defp answer({:ok, %Req.Response{status: 200, body: body}}) do
    choice = body |> Map.get("choices", []) |> List.first(%{})
    model = Map.get(body, "model")

    {:ok,
     %{
       json: decode(get_in(choice, ["message", "content"])),
       model: model,
       stop_reason: Map.get(choice, "finish_reason"),
       cost_usd: cost(model, Map.get(body, "usage", %{}))
     }}
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http, status, body}}

  defp answer({:error, reason}), do: {:error, reason}

  # A model that answered with prose where JSON was asked for has given an
  # answer the gate will reject and ask again for. It is not an error here.
  defp decode(nil), do: nil

  defp decode(content) do
    case Jason.decode(content) do
      {:ok, json} when is_map(json) -> json
      _not_an_object -> nil
    end
  end

  defp cost(model, usage) do
    input = Map.get(usage, "prompt_tokens", 0)
    total = Map.get(usage, "total_tokens") || input + Map.get(usage, "completion_tokens", 0)

    Provider.cost(model, input, total - input)
  end
end
