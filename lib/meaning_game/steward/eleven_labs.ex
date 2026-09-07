defmodule MeaningGame.Steward.ElevenLabs do
  @moduledoc """
  ElevenLabs provider for text-to-speech and sound effect generation.

  - TTS: Uses v3 Conversational (`eleven_v3_conversational`) by default, outputting
    MP3 at 44.1 kHz.
  - Sound Generation: Generates sound effects from text prompts using the
    `eleven_text_to_sound_v2` model.
  """
  require Logger

  alias MeaningGame.Steward.Provider

  @sound_gen_url "https://api.elevenlabs.io/v1/sound-generation"
  @default_tts_model "eleven_v3_conversational"
  @default_timeout_ms 3_000

  # ---------------------------------------------------------------------------
  # Text-to-Speech (`speak/2`)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the names of any missing API keys required by ElevenLabs for voice.
  """
  @spec missing_keys(keyword() | map()) :: [String.t()]
  def missing_keys(opts \\ []) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    case api_key(opts, :voice) do
      {:ok, _} -> []
      {:error, _} -> ["ELEVENLABS_API_KEY"]
    end
  end

  @doc """
  Synthesizes speech for one line of text via ElevenLabs TTS API.
  """
  @spec speak(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def speak(line, opts \\ []) do
    with {:ok, key} <- api_key(opts, :voice),
         {:ok, voice_id} <- fetch_voice_id(opts) do
      model = Keyword.get(opts, :model, @default_tts_model)
      timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
      url = "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"

      body = %{
        "text" => line,
        "model_id" => model
      }

      headers = [
        {"xi-api-key", key},
        {"content-type", "application/json"}
      ]

      req_opts =
        [
          url: url,
          params: [output_format: "mp3_44100_128"],
          headers: headers,
          json: body,
          receive_timeout: timeout,
          retry: false
        ]
        |> Keyword.merge(Provider.http_options(__MODULE__))

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: 200, body: audio} = resp} when is_binary(audio) ->
          characters = parse_character_count(resp, line)
          cost_usd = Provider.character_cost(model, characters)

          {:ok,
           %{
             audio: audio,
             format: :mp3,
             meta: %{
               provider: __MODULE__,
               voice_id: voice_id,
               model: model,
               characters: characters,
               cost_usd: cost_usd
             }
           }}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, parse_error(status, body)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Sound Generation (`generate/1`)
  # ---------------------------------------------------------------------------

  @typedoc "A sound generation request"
  @type request :: %{
          required(:text) => String.t(),
          optional(:duration_seconds) => float() | nil,
          optional(:prompt_influence) => float() | nil,
          optional(:loop) => boolean(),
          optional(:output_format) => String.t(),
          optional(:model) => String.t(),
          optional(:api_key) => String.t() | nil,
          optional(:timeout_ms) => pos_integer()
        }

  @typedoc "A sound generation response"
  @type response :: %{
          bytes: binary(),
          model: String.t(),
          character_cost: non_neg_integer(),
          cost_usd: float()
        }

  @doc """
  Generates sound effects from text prompts using the `eleven_text_to_sound_v2` model.
  """
  @spec generate(request() | keyword() | map()) :: {:ok, response()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request, :effects) do
      model = Map.get(request, :model) || Map.get(request, "model", "eleven_text_to_sound_v2")

      output_format =
        Map.get(request, :output_format) ||
          Map.get(request, :format) ||
          Map.get(request, "output_format") ||
          Map.get(request, "format", "mp3_44100_128")

      timeout_ms = Map.get(request, :timeout_ms) || Map.get(request, "timeout_ms", 30_000)

      params = if output_format, do: [output_format: output_format], else: []

      [
        url: @sound_gen_url,
        params: params,
        headers: [{"xi-api-key", key}],
        json: sound_body(request),
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))
      |> Req.post()
      |> answer_generate(model)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sound_body(request) do
    text = Map.get(request, :text) || Map.get(request, "text")

    %{text: text}
    |> maybe_put(
      :duration_seconds,
      Map.get(request, :duration_seconds) || Map.get(request, "duration_seconds")
    )
    |> maybe_put(
      :prompt_influence,
      Map.get(request, :prompt_influence) || Map.get(request, "prompt_influence")
    )
    |> maybe_put_loop(Map.get(request, :loop) || Map.get(request, "loop"))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp maybe_put_loop(map, true), do: Map.put(map, :loop, true)
  defp maybe_put_loop(map, _), do: map

  defp answer_generate({:ok, %Req.Response{status: 200, body: body, headers: headers}}, model) do
    character_cost = parse_character_cost(headers)

    {:ok,
     %{
       bytes: body,
       model: model,
       character_cost: character_cost,
       cost_usd: Provider.character_cost(model, character_cost)
     }}
  end

  defp answer_generate({:ok, %Req.Response{status: status, body: body}}, _model) do
    {:error, {:http, status, Provider.decode_body(body)}}
  end

  defp answer_generate({:error, reason}, _model), do: {:error, reason}

  defp parse_character_cost(headers) do
    Enum.find_value(headers, 0, fn {k, v} ->
      if String.downcase(to_string(k)) == "character-cost" do
        val = if is_list(v), do: List.first(v), else: v

        case Integer.parse(to_string(val)) do
          {int, _} -> int
          :error -> 0
        end
      end
    end)
  end

  defp parse_error(status, %{"detail" => %{"message" => message}}) when is_binary(message) do
    {:eleven_labs, status, message}
  end

  defp parse_error(status, %{"detail" => message}) when is_binary(message) do
    {:eleven_labs, status, message}
  end

  defp parse_error(status, %{"message" => message}) when is_binary(message) do
    {:eleven_labs, status, message}
  end

  defp parse_error(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_error(status, decoded)
      _ -> {:http, status, body}
    end
  end

  defp parse_error(status, body), do: {:http, status, body}

  defp api_key(opts, job_kind) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :api_key) ->
        case Keyword.get(opts, :api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      Keyword.has_key?(opts, :elevenlabs_api_key) ->
        case Keyword.get(opts, :elevenlabs_api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      true ->
        case config_key(job_kind) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end
    end
  end

  defp api_key(request, job_kind) when is_map(request) do
    cond do
      Map.has_key?(request, :api_key) ->
        case Map.get(request, :api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      Map.has_key?(request, "api_key") ->
        case Map.get(request, "api_key") do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      Map.has_key?(request, :elevenlabs_api_key) ->
        case Map.get(request, :elevenlabs_api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      Map.has_key?(request, "elevenlabs_api_key") ->
        case Map.get(request, "elevenlabs_api_key") do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      true ->
        case config_key(job_kind) do
          key when is_binary(key) and key != "" ->
            {:ok, key}

          _ ->
            Logger.error("ELEVENLABS_API_KEY is not set; Foley cannot proceed")
            {:error, :no_api_key}
        end
    end
  end

  defp fetch_voice_id(opts) do
    case Keyword.get(opts, :voice_id) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:ok, "JBFqnCBsd6RMkjVDRZzb"}
    end
  end

  defp config_key(job_kind) do
    try do
      role = MeaningGame.Steward.role(:foley)
      job_role = MeaningGame.Steward.role(:foley, job_kind)

      job_role[:api_key] ||
        job_role[:elevenlabs_api_key] ||
        role[:elevenlabs_api_key] ||
        role[:api_key]
    rescue
      _ -> nil
    end
  end

  defp parse_character_count(resp, line) do
    case Req.Response.get_header(resp, "character-cost") do
      [val | _] ->
        case Integer.parse(val) do
          {chars, _} -> chars
          :error -> String.length(line)
        end

      _ ->
        String.length(line)
    end
  end
end
