defmodule Keeper.HTTP do
  @moduledoc """
  Streams a POST with Req, feeds each SSE event to a reducer, and measures
  time-to-first-answer-token and total wall time. Every adapter goes through here.
  """

  def stream_post(url, headers, body, reducer, state, opts \\ []) do
    t0 = System.monotonic_time(:millisecond)
    state = Map.merge(state, %{t0: t0, ttft_ms: nil, raw: [], sse_buf: ""})

    into = fn {:data, chunk}, {req, resp} ->
      st = Req.Response.get_private(resp, :st) || state

      receive do
        :keeper_cancel -> throw({:keeper_cancelled, st})
      after
        0 -> :ok
      end

      st =
        if resp.status == 200 do
          {events, rest} = Keeper.SSE.feed(st.sse_buf, chunk)
          Enum.reduce(events, %{st | sse_buf: rest}, reducer)
        else
          %{st | raw: [st.raw | [chunk]]}
        end

      {:cont, {req, Req.Response.put_private(resp, :st, st)}}
    end

    result =
      try do
        Req.post(url,
          headers: headers,
          body: body,
          into: into,
          retry: false,
          # Req 0.7: pool_timeout lives under :finch, and :finch cannot be combined with :connect_options.
          finch: [pool_timeout: 30_000],
          receive_timeout: Keyword.get(opts, :timeout, 900_000)
        )
      catch
        {:keeper_cancelled, _st} -> {:error, :cancelled}
      end

    total = System.monotonic_time(:millisecond) - t0

    case result do
      {:ok, %Req.Response{status: 200} = resp} ->
        {:ok, Map.put(Req.Response.get_private(resp, :st) || state, :total_ms, total)}

      {:ok, %Req.Response{status: status} = resp} ->
        st = Req.Response.get_private(resp, :st) || state
        {:error, {:http, status, IO.iodata_to_binary(st.raw)}}

      {:error, e} ->
        {:error, e}
    end
  end

  @doc "Stamp the first-answer-token time once."
  def stamp_ttft(%{ttft_ms: nil, t0: t0} = st), do: %{st | ttft_ms: System.monotonic_time(:millisecond) - t0}
  def stamp_ttft(st), do: st
end
