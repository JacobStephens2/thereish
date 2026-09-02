defmodule Keeper.Adapter.ChatCompletions do
  @moduledoc "Shared wire code for OpenAI-shaped chat-completions endpoints (OpenAI itself and Baseten)."

  import Keeper.Adapter, only: [put_if: 3]
  alias Keeper.HTTP

  def complete(req, base_url, api_key, style, opts) do
    headers = [{"authorization", "Bearer " <> api_key}, {"content-type", "application/json"}]

    state = %{
      text: [],
      usage: %{input_tokens: 0, output_tokens: 0},
      model: req.model,
      stop_reason: nil,
      reasoning_chars: 0,
      error: nil
    }

    case HTTP.stream_post(base_url <> "/chat/completions", headers, Jason.encode!(body(req, style)), &on_event/2, state, opts) do
      {:ok, %{error: nil} = st} -> {:ok, Keeper.Adapter.finish(req, st)}
      {:ok, %{error: err}} -> {:error, {:stream_error, err}}
      {:error, e} -> {:error, e}
    end
  end

  def body(req, style) do
    messages =
      if(req[:system], do: [%{role: "system", content: req.system}], else: []) ++
        [%{role: "user", content: req.user}]

    %{model: req.model, stream: true, stream_options: %{include_usage: true}, messages: messages}
    |> put_if(:reasoning_effort, req[:effort])
    |> Map.put(max_tokens_key(style), req.max_tokens)
    |> put_if(
      :response_format,
      if(req[:schema],
        do: %{type: "json_schema", json_schema: %{name: req[:schema_name] || "output", strict: true, schema: req.schema}}
      )
    )
  end

  # OpenAI's reasoning models reject `max_tokens`; Baseten's vLLM-style endpoint takes `max_tokens`.
  defp max_tokens_key(:openai), do: :max_completion_tokens
  defp max_tokens_key(:baseten), do: :max_tokens

  defp on_event(%{data: "[DONE]"}, st), do: st

  defp on_event(%{data: d}, st) do
    m = Jason.decode!(d)

    st =
      case m do
        %{"error" => e} -> %{st | error: e}
        _ -> st
      end

    st =
      case m["usage"] do
        nil ->
          st

        u ->
          %{
            st
            | usage: %{
                input_tokens: u["prompt_tokens"] || 0,
                output_tokens: u["completion_tokens"] || 0,
                reasoning_tokens: get_in(u, ["completion_tokens_details", "reasoning_tokens"])
              }
          }
      end

    case m["choices"] do
      [%{"delta" => delta} = choice | _] ->
        st =
          case delta["content"] do
            nil -> st
            "" -> st
            t -> %{HTTP.stamp_ttft(st) | text: [st.text | [t]]}
          end

        st =
          case delta["reasoning_content"] || delta["reasoning"] do
            nil -> st
            r -> %{st | reasoning_chars: st.reasoning_chars + String.length(r)}
          end

        case choice["finish_reason"] do
          nil -> st
          fr -> %{st | stop_reason: fr}
        end

      _ ->
        st
    end
  end
end
