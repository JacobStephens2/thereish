defmodule Keeper.Adapter.Anthropic do
  @moduledoc """
  Messages API over raw HTTP with SSE streaming.
  Fable 5.1 rules honoured here: no `thinking` param (always on), no temperature/top_p, no prefill,
  effort + JSON schema in `output_config`, server-side refusal fallbacks opted in via beta header,
  and `stop_reason: "refusal"` surfaced before anyone reads content.
  """
  @behaviour Keeper.Adapter

  import Keeper.Adapter, only: [put_if: 3]
  alias Keeper.HTTP

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @fallback_beta "server-side-fallback-2026-07-01"

  @impl true
  def complete(req, opts \\ []) do
    headers =
      [
        {"x-api-key", System.fetch_env!("ANTHROPIC_API_KEY")},
        {"anthropic-version", @version},
        {"content-type", "application/json"}
      ] ++ if(req[:fallbacks], do: [{"anthropic-beta", @fallback_beta}], else: [])

    state = %{
      text: [],
      usage: %{input_tokens: 0, output_tokens: 0},
      model: req.model,
      stop_reason: nil,
      stop_details: nil,
      fallbacks: [],
      thinking_deltas: 0,
      iterations: nil,
      error: nil
    }

    case HTTP.stream_post(@url, headers, Jason.encode!(body(req)), &on_event/2, state, opts) do
      {:ok, %{error: nil} = st} -> {:ok, Keeper.Adapter.finish(req, st)}
      {:ok, %{error: err}} -> {:error, {:stream_error, err}}
      {:error, e} -> {:error, e}
    end
  end

  def body(req) do
    %{model: req.model, max_tokens: req.max_tokens, stream: true, messages: [%{role: "user", content: req.user}]}
    |> put_if(:system, req[:system])
    |> put_if(:output_config, output_config(req))
    |> put_if(:fallbacks, if(req[:fallbacks], do: "default"))
  end

  defp output_config(req) do
    cfg =
      %{}
      |> put_if(:effort, req[:effort])
      |> put_if(:format, if(req[:schema], do: %{type: "json_schema", schema: req.schema}))

    if cfg == %{}, do: nil, else: cfg
  end

  # --- SSE reducer -----------------------------------------------------------
  defp on_event(%{event: "message_start", data: d}, st) do
    m = Jason.decode!(d)["message"]
    u = m["usage"] || %{}

    %{
      st
      | model: m["model"],
        usage: %{
          input_tokens: u["input_tokens"] || 0,
          output_tokens: u["output_tokens"] || 0,
          cache_read: u["cache_read_input_tokens"],
          cache_write: u["cache_creation_input_tokens"]
        }
    }
  end

  defp on_event(%{event: "content_block_start", data: d}, st) do
    case Jason.decode!(d)["content_block"] do
      %{"type" => "fallback"} = b -> %{st | fallbacks: st.fallbacks ++ [b]}
      _ -> st
    end
  end

  defp on_event(%{event: "content_block_delta", data: d}, st) do
    case Jason.decode!(d)["delta"] do
      %{"type" => "text_delta", "text" => ""} -> st
      %{"type" => "text_delta", "text" => t} -> %{HTTP.stamp_ttft(st) | text: [st.text | [t]]}
      %{"type" => "thinking_delta"} -> %{st | thinking_deltas: st.thinking_deltas + 1}
      _ -> st
    end
  end

  defp on_event(%{event: "message_delta", data: d}, st) do
    m = Jason.decode!(d)
    delta = m["delta"] || %{}
    u = m["usage"] || %{}

    %{
      st
      | stop_reason: delta["stop_reason"] || st.stop_reason,
        stop_details: delta["stop_details"] || st.stop_details,
        usage: Map.merge(st.usage, %{output_tokens: u["output_tokens"] || st.usage.output_tokens, thinking_tokens: get_in(u, ["output_tokens_details", "thinking_tokens"])}),
        iterations: u["iterations"] || st.iterations
    }
  end

  defp on_event(%{event: "error", data: d}, st), do: %{st | error: Jason.decode!(d)}
  defp on_event(_, st), do: st
end
