defmodule Thereish.Steward.GateTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  import Thereish.StewardFixtures, only: [recorded: 1, response: 1]

  alias Thereish.Steward
  alias Thereish.Steward.Gate

  @prompt %{
    system: "Answer the question.",
    user: "One accepted answer, please.",
    schema_name: "gate_answer",
    schema: %{
      "type" => "object",
      "properties" => %{"answer" => %{"type" => "string"}},
      "required" => ["answer"],
      "additionalProperties" => false
    }
  }
  @accepted %{"answer" => "accepted"}

  test "identical concurrent questions return the first accepted answer and shut down losers" do
    task = answering(requests: 3, retries: 0)

    assert_receive {:asked, first, body}, 1_000
    assert_receive {:asked, winner, same_body}, 1_000
    assert_receive {:asked, third, third_body}, 1_000
    assert body == same_body
    assert body == third_body
    assert body["model"] == Steward.role(:assayer).model
    first_ref = Process.monitor(first)
    third_ref = Process.monitor(third)

    reply(winner, @accepted)

    assert {:ok, %{json: @accepted, attempts: 1}} = Task.await(task)
    assert_receive {:DOWN, ^first_ref, :process, ^first, :killed}, 1_000
    assert_receive {:DOWN, ^third_ref, :process, ^third, :killed}, 1_000
  end

  test "an early returned provider error does not preempt another request's success" do
    task = answering(requests: 2, retries: 2)
    assert_receive {:asked, failed, _body}, 1_000
    assert_receive {:asked, winner, _body}, 1_000
    failed_ref = Process.monitor(failed)

    send(failed, {:error, 503, "first request failed"})
    assert_receive {:DOWN, ^failed_ref, :process, ^failed, :normal}, 1_000
    reply(winner, @accepted)

    assert {:ok, %{json: @accepted, attempts: 1}} = Task.await(task)
    refute_received {:asked, _, _}
  end

  test "all failures return the first observed error, without retrying provider errors" do
    task = answering(requests: 3, retries: 2)
    assert_receive {:asked, first, _body}, 1_000
    assert_receive {:asked, second, _body}, 1_000
    assert_receive {:asked, third, _body}, 1_000
    second_ref = Process.monitor(second)

    send(second, {:error, 503, "first observed failure"})
    assert_receive {:DOWN, ^second_ref, :process, ^second, :normal}, 1_000
    send(first, {:error, 500, "later failure"})
    send(third, {:error, 429, "last failure"})

    assert {:error, {:http, 503, "first observed failure"}} = Task.await(task)
    refute_received {:asked, _, _}
  end

  test "a missing request count and counts at or below one ask inline" do
    caller = self()

    recorded(fn conn, _body ->
      assert self() == caller
      send(caller, :asked_inline)
      Req.Test.json(conn, response(Jason.encode!(@accepted)))
    end)

    for count <- [:missing, -1, 0, 1] do
      role = Map.put(Steward.role(:assayer), :retries, 0)

      role =
        if count == :missing,
          do: Map.delete(role, :requests),
          else: Map.put(role, :requests, count)

      assert {:ok, %{json: @accepted, attempts: 1}} = Gate.answer(role, @prompt, &check/1)
      assert_received :asked_inline
      refute_received :asked_inline
    end
  end

  test "each request owns repair feedback, cap retries and the winning answer's provenance" do
    started = System.monotonic_time(:millisecond)
    task = answering(requests: 2, retries: 2)
    assert_receive {:asked, loser, initial}, 1_000
    assert_receive {:asked, winner, ^initial}, 1_000
    winner_seen = System.monotonic_time(:millisecond)

    send(loser, {:reply, response("prose instead of JSON")})
    assert_receive {:asked, ^loser, loser_repair}, 1_000
    assert user(loser_repair) =~ "not a JSON object"

    reply(winner, %{"answer" => 123})
    assert_receive {:asked, ^winner, winner_repair}, 1_000
    assert user(winner_repair) =~ "schema:"
    refute user(winner_repair) =~ "not a JSON object"

    reply(loser, %{"answer" => "role rejection"})
    assert_receive {:asked, ^loser, loser_second_repair}, 1_000
    assert user(loser_second_repair) =~ "not a JSON object"
    assert user(loser_second_repair) =~ "the role did not accept"
    refute user(loser_second_repair) =~ "schema:"

    cap =
      put_in(response("unfinished answer"), ["choices", Access.at(0), "finish_reason"], "length")

    send(winner, {:reply, cap})
    assert_receive {:asked, ^winner, ^winner_repair}, 1_000

    loser_ref = Process.monitor(loser)
    send(loser, {:error, 503, "loser's usage must not be included"})
    assert_receive {:DOWN, ^loser_ref, :process, ^loser, :normal}, 1_000

    before_accept = System.monotonic_time(:millisecond)
    winning_response = Map.put(response(Jason.encode!(@accepted)), "model", "gpt-6-astra")
    send(winner, {:reply, winning_response})

    assert {:ok, answer} = Task.await(task)
    assert answer.json == @accepted
    assert answer.model == "gpt-6-astra"
    assert answer.attempts == 3
    # Two Gemini responses at $0.00081525 each, then the reported Astra model
    # at $0.000918. The other request's two paid answers contribute nothing.
    assert_in_delta answer.cost_usd, 0.0025485, 1.0e-12
    assert answer.latency_ms >= before_accept - winner_seen
    assert answer.latency_ms <= System.monotonic_time(:millisecond) - started
    refute_received {:asked, _, _}
  end

  test "each request stops after its own retry budget for rejections and either cap reason" do
    for failure <- [:role, :schema, :json, "max_tokens", "length"] do
      task = answering(requests: 2, retries: 1)
      assert_receive {:asked, first, initial}, 1_000
      assert_receive {:asked, second, ^initial}, 1_000

      for pid <- [first, second] do
        reject(pid, failure)
        assert_receive {:asked, ^pid, retry_body}, 1_000

        if is_binary(failure) do
          assert retry_body == initial
        else
          assert user(retry_body) =~ "rejected by the validator"
        end

        ref = Process.monitor(pid)
        reject(pid, failure)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
      end

      if is_binary(failure) do
        assert {:error, {:max_tokens, why}} = Task.await(task)
        assert why =~ "stop_reason=#{failure}"
      else
        assert {:error, {:rejected, _why}} = Task.await(task)
      end

      refute_received {:asked, _, _}
    end
  end

  test "an exception in a linked request exits the caller and its other requests" do
    Process.flag(:trap_exit, true)
    task = answering(requests: 2, retries: 1)
    assert_receive {:asked, failed, _body}, 1_000
    assert_receive {:asked, other, _body}, 1_000
    other_ref = Process.monitor(other)
    %{ref: caller_ref, pid: caller} = task

    send(failed, {:raise, "provider crashed"})

    assert_receive {:DOWN, ^caller_ref, :process, ^caller,
                    {%RuntimeError{message: "provider crashed"}, _stack}},
                   1_000

    assert_receive {:DOWN, ^other_ref, :process, ^other, _reason}, 1_000
    assert_receive {:EXIT, ^caller, _reason}, 1_000
  end

  test "requests are owned by the caller and die when it is killed" do
    Process.flag(:trap_exit, true)
    task = answering(requests: 2, retries: 0)
    assert_receive {:asked, first, _body}, 1_000
    assert_receive {:asked, second, _body}, 1_000
    first_ref = Process.monitor(first)
    second_ref = Process.monitor(second)
    %{ref: caller_ref, pid: caller} = task

    Process.exit(caller, :kill)

    assert_receive {:DOWN, ^caller_ref, :process, ^caller, :killed}, 1_000
    assert_receive {:DOWN, ^first_ref, :process, ^first, :killed}, 1_000
    assert_receive {:DOWN, ^second_ref, :process, ^second, :killed}, 1_000
    assert_receive {:EXIT, ^caller, :killed}, 1_000
  end

  defp answering(opts) do
    test = self()

    recorded(fn conn, body ->
      send(test, {:asked, self(), body})

      receive do
        {:reply, response} -> Req.Test.json(conn, response)
        {:error, status, message} -> Plug.Conn.send_resp(conn, status, message)
        {:raise, message} -> raise message
      after
        10_000 -> flunk("the test did not release the recorded response")
      end
    end)

    role = Map.merge(Steward.role(:assayer), Map.new(opts))
    Task.async(fn -> Gate.answer(role, @prompt, &check/1) end)
  end

  defp check(@accepted), do: :ok
  defp check(_json), do: {:error, "the role did not accept the answer"}

  defp reply(pid, json) do
    send(pid, {:reply, response(Jason.encode!(json))})
  end

  defp reject(pid, :role), do: reply(pid, %{"answer" => "rejected"})
  defp reject(pid, :schema), do: reply(pid, %{"answer" => 123})
  defp reject(pid, :json), do: send(pid, {:reply, response("not JSON")})

  defp reject(pid, cap) do
    response = put_in(response(nil), ["choices", Access.at(0), "finish_reason"], cap)
    send(pid, {:reply, response})
  end

  defp user(body), do: Enum.find(body["messages"], &(&1["role"] == "user"))["content"]
end
