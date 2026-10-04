defmodule Thereish.StewardTest do
  @moduledoc """
  The live Assayer, against recorded responses.

  Everything here asks the same question the couch asks — grade this Attempt's
  Bridges — and checks the things that are true of a grade whatever the model
  said: that both orderings were asked and both were kept, that a malformed
  answer was sent back rather than shown, that a hedged pair of requests was one
  question asked twice, and that a failure is a failure rather than a number.

  The two orderings, their deadline and how they are reconciled are the
  Steward's, in front of the seam, so the tests of them ask
  `Thereish.Steward.assay/2`. The live adapter grades the one ordering it is
  handed, and its own tests ask it for one.

  Nothing here asserts on what the Assayer is asked. The words of the question
  are going to move as the couple calibrate it, and a test that froze them would
  turn every calibration into a test failure. The one thing any of this compares
  is that two hedged requests are byte-identical to each other, which is a fact
  about hedging rather than about the wording.

  The Precedent is the Steward's, not the live adapter's, so the tests of it ask
  `Thereish.Steward.assay/2`: with the live adapter where they watch what the
  provider was asked, and with the Fake where they only need the rule.
  """
  # Which model answers, how often, and how patiently is application
  # configuration, and these tests move it.
  use Thereish.DataCase, async: false

  # A rejected answer is logged, and half of these tests reject one on purpose.
  @moduletag :capture_log

  import Thereish.StewardFixtures

  alias Thereish.Chronicle
  alias Thereish.Rooms.Store
  alias Thereish.Steward
  alias Thereish.Steward.Live
  alias Thereish.Steward.Precedent

  @pair %{bookends: ["lantern", "harbour"], bridges: ["beacon", "cairn"]}

  # The table's ruling on @pair, recorded the way the Room records one: in a
  # Room of its own, proposed by one of its Seats. `said` overrides what the
  # Seats ruled.
  defp overrule(said) do
    {:ok, room} = Store.insert_room("overrule-#{System.unique_integer([:positive])}", 2)
    {:ok, seat} = Store.insert_seat(room.id, Ecto.UUID.generate(), "Melissa", "device-melissa")

    ruling =
      Map.merge(
        %{
          attempt_number: 1,
          proposer_seat_id: seat.id,
          bookends: @pair.bookends,
          bridges: @pair.bridges,
          machine_closeness: 41,
          machine_reasoning: "Original grade.",
          machine_quip: "Not quite.",
          couple_closeness: 100,
          couple_reasoning: "Overruled jointly across all Seats. Recorded as precedent.",
          couple_quip: "House law."
        },
        said
      )

    {room.id, Steward.overrule(room.id, ruling)}
  end

  # Which way round this request asked, named by the Bridge it put first.
  defp ordering(body), do: first_bridge(body, @pair.bridges)

  describe "grading a pair" do
    setup do
      assayer(adapter: Live)
    end

    test "both orderings are graded, and both are kept beside the grade" do
      recorded(fn conn, body ->
        case ordering(body) do
          "beacon" -> Req.Test.json(conn, response(verdict(closeness: 80, reasoning: "Forward.")))
          "cairn" -> Req.Test.json(conn, response(verdict(closeness: 40, reasoning: "Reverse.")))
        end
      end)

      {:ok, verdict} = Steward.assay(@pair)

      # The grade is the mean of the two orderings, and neither of them is lost:
      # a wide gap is the most useful thing to know about a grade that looks
      # wrong, and the couple cannot argue with evidence that was discarded.
      assert verdict.closeness == 60
      assert verdict.meta.forward == 80
      assert verdict.meta.reverse == 40
      assert verdict.reasoning == "Forward."
      assert verdict.meta.reasoning_reverse == "Reverse."
    end

    test "the quip and the provenance ride along with the grade" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(quip: "Both of you went looking for the shore.")))
      end)

      {:ok, verdict} = Steward.assay(@pair)

      assert verdict.quip == "Both of you went looking for the shore."
      assert verdict.meta.model == "gemini-3.8-flash"
      assert verdict.meta.prompt_version == Thereish.Steward.Assay.version()
      assert verdict.meta.cost_usd > 0
    end

    test "the words are the forward ordering's, and the cost is both orderings'" do
      assayer(requests: 1, retries: 0)

      recorded(fn conn, body ->
        case ordering(body) do
          "beacon" ->
            Req.Test.json(conn, response(verdict(reasoning: "Forward.", quip: "Forward joke.")))

          "cairn" ->
            Req.Test.json(conn, response(verdict(reasoning: "Reverse.", quip: "Reverse joke.")))
        end
      end)

      {:ok, one} = Live.assay(@pair, @pair.bridges)
      {:ok, verdict} = Steward.assay(@pair)

      assert verdict.reasoning == "Forward."
      assert verdict.quip == "Forward joke."
      assert verdict.meta.reasoning_reverse == "Reverse."
      # Every recording spends the same tokens, so two orderings cost two of one.
      assert verdict.meta.cost_usd == 2 * one.cost_usd
    end

    test "a missing ordering is no Verdict, not half of one" do
      assayer(requests: 1, retries: 0)

      recorded(fn conn, body ->
        case ordering(body) do
          "beacon" -> Req.Test.json(conn, response(verdict(closeness: 80)))
          "cairn" -> Plug.Conn.send_resp(conn, 503, "upstream is having a moment")
        end
      end)

      assert {:error, {:http, 503, _body}} = Steward.assay(@pair)
      role = Steward.role(:assayer)
      assert :miss = Precedent.get(role.model, Thereish.Steward.Assay.version(), @pair)
    end

    test "when both orderings fail, the forward ordering's reason is the one reported" do
      assayer(requests: 1, retries: 0)

      recorded(fn conn, body ->
        case ordering(body) do
          "beacon" -> Plug.Conn.send_resp(conn, 503, "forward")
          "cairn" -> Plug.Conn.send_resp(conn, 500, "reverse")
        end
      end)

      assert {:error, {:http, 503, _body}} = Steward.assay(@pair)
    end
  end

  describe "the validator has the last word" do
    setup do
      assayer(requests: 1, retries: 2)
    end

    test "an answer the schema rejects is asked for again rather than shown" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, ordering(body)) do
          # A closeness the ladder has no rung for. The schema catches it, and
          # what the players see is the corrected answer.
          1 -> Req.Test.json(conn, response(verdict(closeness: 4000)))
          _ -> Req.Test.json(conn, response(verdict(closeness: 55)))
        end
      end)

      assert {:ok, verdict} = Live.assay(@pair, @pair.bridges)
      assert verdict.closeness == 55
      assert Agent.get(counts, &Map.values/1) == [2]
    end

    test "an answer that is not JSON at all is asked for again" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, ordering(body)) do
          1 -> Req.Test.json(conn, response("These two words are pretty close, I'd say."))
          _ -> Req.Test.json(conn, response(verdict(closeness: 55)))
        end
      end)

      assert {:ok, verdict} = Live.assay(@pair, @pair.bridges)
      assert verdict.closeness == 55
    end

    test "a model that never produces a valid answer is no verdict, not a crash" do
      assayer(requests: 1, retries: 1)

      recorded(fn conn, _body -> Req.Test.json(conn, response(verdict(closeness: 4000))) end)

      assert {:error, {:rejected, why}} = Live.assay(@pair, @pair.bridges)
      assert why =~ "schema"
    end
  end

  describe "hedging" do
    setup do
      assayer(requests: 2, retries: 0)
    end

    test "fires two identical requests to one model and takes the first answer" do
      counts = counts()
      test = self()

      recorded(fn conn, body ->
        ordering = ordering(body)
        send(test, {:asked, ordering, body})

        case asked(counts, ordering) do
          1 ->
            # Both requests are in flight before either is answered, which is
            # what makes this hedging rather than a retry.
            once_asked(counts, ordering, 2)
            Req.Test.json(conn, response(verdict(closeness: 80)))

          _ ->
            # The straggler. It answers differently so that a reveal built on it
            # would be visible, and late enough that taking it would be a choice
            # rather than a race.
            Process.sleep(300)
            Req.Test.json(conn, response(verdict(closeness: 20)))
        end
      end)

      {:ok, verdict} = Live.assay(@pair, @pair.bridges)

      assert verdict.closeness == 80

      # Identical requests, not a race between two different questions: hedging
      # against a second question would make the grade a coin toss between two
      # distributions (design law 11).
      assert_receive {:asked, "beacon", first}
      assert_receive {:asked, "beacon", second}
      assert first == second
      refute_received {:asked, "cairn", _}
    end
  end

  describe "when the Assayer cannot answer" do
    setup do
      assayer(requests: 1, retries: 0)
    end

    test "a provider that errors is no verdict rather than a zero" do
      recorded(fn conn, _body ->
        Plug.Conn.send_resp(conn, 503, "upstream is having a moment")
      end)

      assert {:error, {:http, 503, _body}} = Live.assay(@pair, @pair.bridges)
    end

    # A recorded response is served in this process rather than over a socket,
    # so what runs out here is the grading's whole budget rather than one
    # request's socket timeout. That is the one that has to hold: the escalation
    # ladder gives up at ten seconds, and it can only do that if the Steward has.
    test "a provider that never answers gives up before the game does" do
      assayer(adapter: Live, requests: 1, retries: 0, deadline_ms: 50)

      recorded(fn conn, _body ->
        Process.sleep(5_000)
        Req.Test.json(conn, response(verdict()))
      end)

      assert {:error, :timeout} = Steward.assay(@pair)
    end
  end

  describe "grading a table" do
    setup do
      assayer(requests: 1, retries: 2)
    end

    # Four players, one grading. Which of them the request lists first is what
    # tells the two orderings apart, exactly as it does at two.
    @table %{
      bookends: ["lantern", "harbour"],
      bridges: ["beacon", "cairn", "lamp", "seagull"]
    }

    defp table_ordering(body), do: first_bridge(body, @table.bridges)

    test "four Bridges are one grading, asked in roster order and its reverse" do
      assayer(adapter: Live)
      counts = counts()

      recorded(fn conn, body ->
        ordering = table_ordering(body)
        asked(counts, ordering)

        case ordering do
          "beacon" ->
            Req.Test.json(
              conn,
              response(
                verdict(closeness: 60, reasoning: "Forward.", furthest: ["beacon", "seagull"])
              )
            )

          "seagull" ->
            Req.Test.json(
              conn,
              response(verdict(closeness: 40, reasoning: "Reverse.", furthest: ["cairn", "lamp"]))
            )
        end
      end)

      {:ok, verdict} = Steward.assay(@table)

      # Two orderings and not twenty-four: roster order against its reverse is
      # the same correction at four that it is at two.
      assert Agent.get(counts, &Map.values/1) == [1, 1]
      assert verdict.closeness == 50
      assert verdict.meta.forward == 60
      assert verdict.meta.reverse == 40
    end

    test "the two furthest words come from the forward ordering" do
      assayer(adapter: Live)

      recorded(fn conn, body ->
        furthest =
          case table_ordering(body) do
            "beacon" -> ["beacon", "seagull"]
            "seagull" -> ["cairn", "lamp"]
          end

        Req.Test.json(conn, response(verdict(furthest: furthest)))
      end)

      {:ok, verdict} = Steward.assay(@table)

      # The two orderings can name different pairs, and the next Attempt's
      # Bookends have to be one pair rather than an average of two.
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "the two furthest words come back as the players wrote them" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["  BEACON ", "Seagull"])))
      end)

      {:ok, verdict} = Live.assay(@table, @table.bridges)

      # A model that shouted a Bridge back has still named that Bridge, and the
      # words about to be shown as the next Bookends are the words somebody typed.
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "a furthest pair naming a word nobody wrote is asked for again" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, table_ordering(body)) do
          # "gull" is not one of the four Bridges. Taking it would send the next
          # Attempt to Bookends nobody at the table chose.
          1 -> Req.Test.json(conn, response(verdict(furthest: ["beacon", "gull"])))
          _ -> Req.Test.json(conn, response(verdict(furthest: ["beacon", "seagull"])))
        end
      end)

      assert {:ok, verdict} = Live.assay(@table, @table.bridges)
      assert verdict.furthest == ["beacon", "seagull"]
      assert Agent.get(counts, &Map.values/1) == [2]
    end

    test "a furthest pair that is not two words is asked for again" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, table_ordering(body)) do
          1 -> Req.Test.json(conn, response(verdict(furthest: ["beacon"])))
          2 -> Req.Test.json(conn, response(verdict(furthest: ["beacon", "cairn", "lamp"])))
          _ -> Req.Test.json(conn, response(verdict(furthest: ["beacon", "seagull"])))
        end
      end)

      assert {:ok, verdict} = Live.assay(@table, @table.bridges)
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "a model that never names two of the words is no verdict, not a guess" do
      assayer(requests: 1, retries: 1)

      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["beacon", "gull"])))
      end)

      assert {:error, {:rejected, why}} = Live.assay(@table, @table.bridges)
      assert why =~ "furthest"
    end

    test "every ordering of the same four Bridges is one precedent" do
      assayer(adapter: Live, requests: 1, retries: 0)
      counts = counts()

      recorded(fn conn, body ->
        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            Req.Test.json(conn, quip_response("Table joke."))

          _ ->
            asked(counts, table_ordering(body))

            Req.Test.json(
              conn,
              response(verdict(closeness: 33, furthest: ["beacon", "seagull"]))
            )
        end
      end)

      assert {:ok, _} = Steward.assay(@table)
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      shuffled = %{@table | bridges: ["lamp", "seagull", "beacon", "cairn"]}

      assert {:ok, verdict} = Steward.assay(shuffled)
      assert verdict.closeness == 33
      # The whole point of the cache: the same words meeting again get the same
      # grade, whatever order the Seats were filled in (design law 1).
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "a cached Verdict carries the two furthest words with it" do
      assayer(adapter: Live, requests: 1, retries: 0)

      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["beacon", "seagull"])))
      end)

      assert {:ok, _} = Steward.assay(@table)
      assert {:ok, cached} = Steward.assay(@table)

      # A cache hit that lost the furthest pair would replay the grade but not
      # the game: those two words are the next Attempt's Bookends.
      assert cached.furthest == ["beacon", "seagull"]
    end
  end

  describe "the verdict cache is the precedent" do
    setup do
      assayer(adapter: Live, requests: 1, retries: 0)
    end

    test "a Precedent hit's fresh-Quip request carries prior Quips in user content" do
      test_pid = self()

      request = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        player_bridges: [
          %{player: "Jacob", bridge: "beacon"},
          %{player: "Melissa", bridge: "cairn"}
        ]
      }

      chronicle = [
        %{
          attempts: [
            %{verdicts: [%{quip: "Jacob brought the lighthouse, Melissa brought the dock."}]}
          ]
        }
      ]

      recorded(fn conn, body ->
        [%{"content" => user}] = Enum.filter(body["messages"], &(&1["role"] == "user"))

        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            send(test_pid, {:quip_user, user})
            Req.Test.json(conn, quip_response("A fresh joke about tonight."))

          "verdict" ->
            send(test_pid, {:verdict_user, user})
            Req.Test.json(conn, response(verdict(closeness: 77, reasoning: "First run.")))
        end
      end)

      assert {:ok, _first} = Steward.assay(request, chronicle: chronicle)
      assert_receive {:verdict_user, graded_user}
      assert graded_user =~ "Jacob brought the lighthouse, Melissa brought the dock."
      assert graded_user =~ ~r/constructions already used/i

      assert {:ok, second} = Steward.assay(request, chronicle: chronicle)
      assert second.meta.precedent_hit == true
      assert_receive {:quip_user, quip_user}
      assert quip_user =~ "Jacob brought the lighthouse, Melissa brought the dock."
      assert quip_user =~ ~r/constructions already used/i
    end

    test "a repeated Attempt inherits closeness, reasoning and furthest Bridges, and writes a fresh quip" do
      counts = counts()

      recorded(fn conn, body ->
        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            Req.Test.json(conn, quip_response("A fresh joke about tonight."))

          "verdict" ->
            asked(counts, ordering(body))

            Req.Test.json(
              conn,
              response(
                verdict(
                  closeness: 77,
                  reasoning: "First run.",
                  quip: "Original quip.",
                  furthest: ["beacon", "cairn"]
                )
              )
            )
        end
      end)

      assert {:ok, verdict1} = Steward.assay(@pair)
      assert verdict1.closeness == 77
      assert verdict1.quip == "Original quip."
      refute Map.get(verdict1.meta, :precedent_hit, false)
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      # Subsequent call with the exact same pair is a Precedent hit:
      # inherits closeness, reasoning and furthest pair, and gets a fresh quip
      assert {:ok, verdict2} = Steward.assay(@pair)
      assert verdict2.closeness == 77
      assert verdict2.reasoning == "First run."
      assert verdict2.furthest == ["beacon", "cairn"]
      assert verdict2.quip == "A fresh joke about tonight."
      assert verdict2.meta.precedent_hit == true
      assert verdict2.meta.cost_usd > 0
      assert is_integer(verdict2.meta.latency_ms)
      # Did not grade the two orderings again!
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "a failed quip request falls back to the cached quip" do
      recorded(fn conn, body ->
        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            Plug.Conn.send_resp(conn, 500, "quip model failed")

          "verdict" ->
            Req.Test.json(
              conn,
              response(
                verdict(
                  closeness: 77,
                  reasoning: "First run.",
                  quip: "Original quip.",
                  furthest: ["beacon", "cairn"]
                )
              )
            )
        end
      end)

      assert {:ok, verdict1} = Steward.assay(@pair)
      assert verdict1.quip == "Original quip."

      # On Precedent hit, quip request fails (500) and falls back to cached quip
      assert {:ok, verdict2} = Steward.assay(@pair)
      assert verdict2.closeness == 77
      assert verdict2.reasoning == "First run."
      assert verdict2.furthest == ["beacon", "cairn"]
      assert verdict2.quip == "Original quip."
      assert verdict2.meta.precedent_hit == true
    end

    test "a slow quip request falls back to the cached quip" do
      assayer(adapter: Live, requests: 1, retries: 0, timeout_ms: 50)

      recorded(fn conn, body ->
        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            Process.sleep(200)
            Req.Test.json(conn, quip_response("Too slow."))

          "verdict" ->
            Req.Test.json(
              conn,
              response(
                verdict(
                  closeness: 77,
                  reasoning: "First run.",
                  quip: "Original quip.",
                  furthest: ["beacon", "cairn"]
                )
              )
            )
        end
      end)

      assert {:ok, verdict1} = Steward.assay(@pair)
      assert verdict1.quip == "Original quip."

      # On Precedent hit, quip request exceeds timeout and falls back
      assert {:ok, verdict2} = Steward.assay(@pair)
      assert verdict2.closeness == 77
      assert verdict2.reasoning == "First run."
      assert verdict2.quip == "Original quip."
      assert verdict2.meta.precedent_hit == true
    end

    test "the reverse ordering hits the same cached precedent" do
      counts = counts()

      recorded(fn conn, body ->
        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            Req.Test.json(conn, quip_response("Reverse quip."))

          _ ->
            asked(counts, ordering(body))
            Req.Test.json(conn, response(verdict(closeness: 77, reasoning: "First run.")))
        end
      end)

      assert {:ok, _} = Steward.assay(@pair)
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      reversed = %{@pair | bridges: Enum.reverse(@pair.bridges)}
      assert {:ok, verdict} = Steward.assay(reversed)
      assert verdict.closeness == 77
      assert verdict.reasoning == "First run."
      assert verdict.quip == "Reverse quip."
      assert verdict.meta.precedent_hit == true
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "a differing prompt version misses the cache and calls the provider" do
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 77, reasoning: "First run.")))
      end)

      assert {:ok, verdict1} = Steward.assay(@pair)
      assert verdict1.closeness == 77
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      assayer(prompt_version: "a-different-question")

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 85, reasoning: "New prompt version.")))
      end)

      assert {:ok, verdict2} = Steward.assay(@pair)
      assert verdict2.closeness == 85
      assert verdict2.reasoning == "New prompt version."
      assert Agent.get(counts, &Map.values/1) == [2, 2]
    end

    test "Steward.assay returns the cached precedent instantly" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(closeness: 90, reasoning: "Instant.")))
      end)

      assert {:ok, verdict1} = Steward.assay(@pair)
      assert verdict1.closeness == 90

      assert {:ok, verdict2} = Steward.assay(@pair)
      assert verdict2.closeness == 90
      assert verdict2.reasoning == "Instant."
      assert verdict2.meta.latency_ms < 50
    end

    test "an overruled key returns the couple's ruling afterwards" do
      counts = counts()

      recorded(fn conn, body ->
        case body["response_format"]["json_schema"]["name"] do
          "quip" ->
            Req.Test.json(conn, quip_response("House law."))

          _ ->
            asked(counts, ordering(body))
            Req.Test.json(conn, response(verdict(closeness: 41, reasoning: "Original grade.")))
        end
      end)

      assert {:ok, verdict1} = Steward.assay(@pair)
      assert verdict1.closeness == 41
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      assert {_room_id, {:ok, _}} = overrule(%{})

      assert {:ok, verdict2} = Steward.assay(@pair)
      assert verdict2.closeness == 100
      assert verdict2.reasoning == "Overruled jointly across all Seats. Recorded as precedent."
      assert verdict2.quip == "House law."
      # Did not call grading again!
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "a recorded overrule is the Chronicle's row and the Precedent at once" do
      assert {room_id, {:ok, row}} = overrule(%{couple_closeness: 95})

      assert [recorded] = Chronicle.overrules(room_id)
      assert recorded.id == row.id
      assert recorded.couple_closeness == 95
      assert recorded.machine_closeness == 41

      assert {:ok, verdict} = Steward.assay(@pair)
      assert verdict.closeness == 95
      assert verdict.reasoning == "Overruled jointly across all Seats. Recorded as precedent."
    end

    test "a ruling whose Precedent write fails leaves no Chronicle overrule row" do
      # The Chronicle row needs no Quip, and the Precedent does: the first write
      # lands inside the transaction and the second refuses it.
      assert {room_id, {:error, %Ecto.Changeset{}}} = overrule(%{couple_quip: nil})

      assert Chronicle.overrules(room_id) == []
      role = Steward.role(:assayer)
      assert :miss = Precedent.get(role.model, Thereish.Steward.Assay.version(), @pair)
    end

    test "a ruling whose Chronicle row fails leaves the Precedent alone" do
      assert {room_id, {:error, %Ecto.Changeset{}}} = overrule(%{couple_closeness: nil})

      assert Chronicle.overrules(room_id) == []
      role = Steward.role(:assayer)
      assert :miss = Precedent.get(role.model, Thereish.Steward.Assay.version(), @pair)
    end
  end

  describe "the Live adapter answers only the provider act" do
    setup do
      assayer(requests: 1, retries: 2)
    end

    test "its assay grades on every call and leaves the Precedent to the Steward" do
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 77)))
      end)

      assert {:ok, _} = Live.assay(@pair, @pair.bridges)
      assert {:ok, again} = Live.assay(@pair, @pair.bridges)

      refute Map.has_key?(again, :precedent_hit)
      assert Agent.get(counts, &Map.values/1) == [2]
      role = Steward.role(:assayer)
      assert :miss = Precedent.get(role.model, Thereish.Steward.Assay.version(), @pair)
    end

    test "its quip is one request that answers the Quip and what it cost" do
      test_pid = self()
      prior = "Jacob brought the lighthouse, Melissa brought the dock."

      recorded(fn conn, body ->
        [%{"content" => user}] = Enum.filter(body["messages"], &(&1["role"] == "user"))
        send(test_pid, {:quip, body["response_format"]["json_schema"]["name"], user})
        Req.Test.json(conn, quip_response("A fresh joke about tonight."))
      end)

      assert {:ok, %{quip: "A fresh joke about tonight.", meta: %{cost_usd: cost}}} =
               Live.quip(Map.put(@pair, :prior_quips, [prior]))

      assert cost > 0
      assert_received {:quip, "quip", user}
      assert user =~ prior
      assert user =~ ~r/constructions already used/i
    end

    test "its quip is not asked again when it fails, whatever the role's retries" do
      counts = counts()

      recorded(fn conn, _body ->
        asked(counts, :quip)
        Plug.Conn.send_resp(conn, 500, "quip model failed")
      end)

      assert {:error, _reason} = Live.quip(@pair)
      assert Agent.get(counts, &Map.get(&1, :quip)) == 1
    end
  end

  describe "the Precedent sits in front of the seam, with the Fake Assayer" do
    # The Fake answers every test that is not about the provider, so the rule
    # that the grade shown is the precedent (ADR-0006) is tested here through
    # the Steward and nothing that knows a provider exists.
    # Whatever the Fake writes, so these tests are about whose Quip is shown
    # rather than how the Fake words it.
    defp the_fake_quip do
      {:ok, %{quip: quip}} = Thereish.Steward.Fake.quip(@pair)
      quip
    end

    defp cached_quip(quip) do
      {_room_id, {:ok, _}} =
        overrule(%{
          couple_closeness: 64,
          couple_reasoning: "Ruled at the table.",
          couple_quip: quip
        })
    end

    test "a repeated Attempt is answered from the Precedent, not graded again" do
      fake(assay_capture: self())

      assert {:ok, first} = Steward.assay(@pair)
      assert_received {:assay, _request, ["beacon", "cairn"]}
      assert_received {:assay, _request, ["cairn", "beacon"]}
      refute_received {:assay, _request, _ordering}
      refute Map.get(first.meta, :precedent_hit, false)

      reversed = %{@pair | bridges: Enum.reverse(@pair.bridges)}
      assert {:ok, second} = Steward.assay(reversed)
      refute_received {:assay, _request, _ordering}

      assert second.meta.precedent_hit == true
      assert second.closeness == first.closeness
      assert second.reasoning == first.reasoning
      assert second.furthest == first.furthest
      assert is_integer(second.meta.latency_ms)
    end

    test "after the players overrule, the same Bookends and Bridges answer their ruling" do
      assert {:ok, graded} = Steward.assay(@pair)
      refute graded.closeness == 100

      assert {_room_id, {:ok, _}} = overrule(%{})

      assert {:ok, verdict} = Steward.assay(@pair)
      assert verdict.closeness == 100
      assert verdict.reasoning == "Overruled jointly across all Seats. Recorded as precedent."
      assert verdict.meta.precedent_hit == true
    end

    test "a Precedent hit gets a fresh Quip from the adapter" do
      cached_quip("The cached quip.")

      assert {:ok, verdict} = Steward.assay(@pair)
      assert verdict.quip == the_fake_quip()
      assert verdict.closeness == 64
      assert verdict.meta.precedent_hit == true
    end

    test "a Precedent hit whose Quip fails answers the cached Quip at no cost" do
      cached_quip("The cached quip.")
      fake(mode: :unavailable)

      assert {:ok, verdict} = Steward.assay(@pair)
      assert verdict.quip == "The cached quip."
      assert verdict.closeness == 64
      assert verdict.meta.cost_usd == 0.0
      assert verdict.meta.precedent_hit == true
    end

    test "a Precedent hit whose Quip is slow answers the cached Quip at no cost" do
      cached_quip("The cached quip.")
      assayer(quip_timeout_ms: 20)
      fake(delay_ms: 200)

      assert {:ok, verdict} = Steward.assay(@pair)
      assert verdict.quip == "The cached quip."
      assert verdict.meta.cost_usd == 0.0
      assert verdict.meta.precedent_hit == true
      assert verdict.meta.latency_ms < 200
    end
  end

  describe "both orderings are reconciled in front of the seam, with the Fake Assayer" do
    test "each ordering is asked once, and the Verdict carries both" do
      fake(assay_capture: self())

      table = %{bookends: ["lantern", "harbour"], bridges: ["cairn", "cairo", "cable", "beacon"]}

      assert {:ok, verdict} = Steward.assay(table)

      assert_received {:assay, _request, ["cairn", "cairo", "cable", "beacon"]}
      assert_received {:assay, _request, ["beacon", "cable", "cairo", "cairn"]}
      refute_received {:assay, _request, _ordering}

      # The Fake's arithmetic grades both orderings 27, and its tie-break names
      # a different furthest pair in each; the Verdict names the forward one's.
      assert verdict.closeness == 27
      assert verdict.meta.forward == 27
      assert verdict.meta.reverse == 27
      assert verdict.furthest == ["cairn", "beacon"]
      assert verdict.reasoning =~ ~s("cairn" and "beacon")
      assert verdict.meta.reasoning_reverse =~ ~s("beacon" and "cable")
    end

    test "the Verdict carries the Assayer role's prompt version, the Precedent's key" do
      assert {:ok, verdict} = Steward.assay(@pair)

      assert verdict.meta.model == "fake"
      assert verdict.meta.prompt_version == Thereish.Steward.Assay.version()
      assert verdict.meta.cost_usd == 0.0
    end

    test "a pair of orderings past the Assayer's deadline is no Verdict" do
      assayer(deadline_ms: 20)
      fake(delay_ms: 500)

      assert {:error, :timeout} = Steward.assay(@pair)
    end

    test "an Assayer that raises is no Verdict, not an exit in the caller" do
      fake(mode: :raise)

      assert {:error, {:exit, {%RuntimeError{}, _stacktrace}}} = Steward.assay(@pair)
    end

    test "an Assayer that cannot answer is no Verdict" do
      fake(mode: :unavailable)

      assert {:error, :no_verdict} = Steward.assay(@pair)
    end
  end

  describe "the Assayer's prior Quips are composed in front of the seam" do
    defp quipped_page(quips) do
      %{
        attempts:
          Enum.map(quips, fn quip -> %{number: 1, bridges: [], verdicts: [%{quip: quip}]} end)
      }
    end

    test "from the Room's Page views and this Page's earlier Attempts" do
      fake(assay_capture: self())

      request =
        @pair
        |> Map.put(:earlier_attempts, [%{number: 1, bookends: [], bridges: [], quip: "sixth"}])
        |> Map.put(:prior_quips, ["a caller's Quip, replaced"])

      chronicle = [quipped_page(["first", "second", "third"]), quipped_page(["fourth", "fifth"])]

      assert {:ok, _verdict} = Steward.assay(request, chronicle: chronicle)
      assert_received {:assay, sent, ["beacon", "cairn"]}
      assert_received {:assay, ^sent, ["cairn", "beacon"]}
      assert sent.prior_quips == ["second", "third", "fourth", "fifth", "sixth"]
    end

    test "as a Room with no Pages when no chronicle is passed" do
      fake(assay_capture: self())

      assert {:ok, _verdict} = Steward.assay(@pair)
      assert_received {:assay, sent, ["beacon", "cairn"]}
      assert_received {:assay, ^sent, ["cairn", "beacon"]}
      assert sent.prior_quips == []
    end
  end

  describe "assay-4" do
    @n_request %{
      bookends: ["lantern", "harbour", "wharf", "dusk"],
      bridges: ["light", "shore", "lamp", "evening"],
      player_bridges: [
        %{player: "Jacob", bridge: "light"},
        %{player: "Melissa", bridge: "shore"},
        %{player: "Ada", bridge: "lamp"},
        %{player: "Sam", bridge: "evening"}
      ]
    }

    test "the prompt lists N Bookends and the rubric says a Bridge spans all of them" do
      prompt = Thereish.Steward.Assay.prompt(@n_request, @n_request.player_bridges)
      quip = Thereish.Steward.Assay.quip_prompt(@n_request, @n_request.player_bridges)

      assert Thereish.Steward.Assay.version() == "assay-4"
      assert prompt.system =~ "whose meaning spans all of them"
      assert prompt.system =~ "any of the bridges"
      assert quip.system =~ "whose meaning spans all of them"
      assert quip.system =~ "any of the bridges"
      assert quip.user =~ ~r/Bookends: LANTERN, HARBOUR, WHARF and DUSK/

      assert prompt.user =~ ~r/Bookends:.*LANTERN/
      assert prompt.user =~ ~r/Bookends:.*HARBOUR/
      assert prompt.user =~ ~r/Bookends:.*WHARF/
      assert prompt.user =~ ~r/Bookends:.*DUSK/
    end

    test "the post-check still requires exactly two furthest words that were actually written" do
      bridges = ["light", "shore", "lamp", "evening"]

      valid = %{
        "reasoning" => "Three of you were at the water and one of you was not.",
        "quip" => "The evening is having its own night.",
        "furthest" => ["light", "evening"],
        "closeness" => 40
      }

      assert Thereish.Steward.Assay.check(valid, bridges) == :ok

      assert {:error, why} =
               Thereish.Steward.Assay.check(%{valid | "furthest" => ["light"]}, bridges)

      assert why =~ "furthest"

      assert {:error, _} =
               Thereish.Steward.Assay.check(
                 %{valid | "furthest" => ["light", "shore", "lamp"]},
                 bridges
               )

      # A Bookend is not a Bridge: naming one of the table's words that nobody
      # wrote as a Bridge is the same rejection as inventing a word.
      assert {:error, why2} =
               Thereish.Steward.Assay.check(
                 %{valid | "furthest" => ["light", "lantern"]},
                 bridges
               )

      assert why2 =~ "furthest"
    end

    test "a recorded live run with N Bookends lists them and grades the set as one Closeness" do
      assayer(requests: 1, retries: 0)
      test_pid = self()

      recorded(fn conn, body ->
        [%{"content" => user}] = Enum.filter(body["messages"], &(&1["role"] == "user"))
        send(test_pid, {:user_prompt, user})

        Req.Test.json(conn, response(verdict(furthest: ["light", "evening"])))
      end)

      assert {:ok, verdict} = Live.assay(@n_request, @n_request.player_bridges)
      assert verdict.closeness in 0..100
      assert verdict.furthest == ["light", "evening"]

      assert_received {:user_prompt, prompt}
      assert prompt =~ "LANTERN"
      assert prompt =~ "HARBOUR"
      assert prompt =~ "WHARF"
      assert prompt =~ "DUSK"
      assert prompt =~ ~r/Bookends: LANTERN, HARBOUR, WHARF and DUSK/
    end

    test "request carries Bookends, Bridges with players' names in roster order, earlier Attempts, and Gives with names" do
      assayer(requests: 1, retries: 0)
      test_pid = self()

      request = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        player_bridges: [
          %{player: "Jacob", bridge: "beacon"},
          %{player: "Melissa", bridge: "cairn"}
        ],
        earlier_attempts: [
          %{
            number: 1,
            bookends: ["pier", "quay"],
            bridges: [
              %{player: "Jacob", bridge: "jetty"},
              %{player: "Melissa", bridge: "dock"}
            ]
          }
        ],
        gives: [
          %{player: "Jacob", give: "foggy coast"},
          %{player: "Melissa", give: "night watch"}
        ]
      }

      recorded(fn conn, body ->
        [%{"content" => user}] = Enum.filter(body["messages"], &(&1["role"] == "user"))
        send(test_pid, {:user_prompt, user})

        Req.Test.json(conn, response(verdict(furthest: ["beacon", "cairn"])))
      end)

      assert {:ok, _graded} = Live.assay(request, request.player_bridges)

      assert_received {:user_prompt, prompt}
      refute_received {:user_prompt, _}

      # Bookends
      assert prompt =~ "LANTERN and HARBOUR"
      # Gives with names
      assert prompt =~ "Jacob gave: foggy coast"
      assert prompt =~ "Melissa gave: night watch"
      # Earlier attempts
      assert prompt =~ "Attempt 1: Bookends: PIER and QUAY"
      assert prompt =~ "Jacob bridged with: jetty"
      assert prompt =~ "Melissa bridged with: dock"

      # The Bridges with their names, in the ordering it was handed.
      {j, _} = :binary.match(prompt, "Jacob bridged with: beacon")
      {m, _} = :binary.match(prompt, "Melissa bridged with: cairn")
      assert j < m
    end

    test "rejects a furthest pair that is not two of the bridges (e.g. naming a Give or hallucinated word)" do
      assayer(requests: 1, retries: 2)
      counts = counts()

      request = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        player_bridges: [
          %{player: "Jacob", bridge: "beacon"},
          %{player: "Melissa", bridge: "cairn"}
        ],
        gives: [%{player: "Jacob", give: "foggy coast"}]
      }

      recorded(fn conn, body ->
        case asked(counts, ordering(body)) do
          # The model mistakenly named a Give instead of a Bridge
          1 -> Req.Test.json(conn, response(verdict(furthest: ["foggy coast", "beacon"])))
          _ -> Req.Test.json(conn, response(verdict(furthest: ["beacon", "cairn"])))
        end
      end)

      assert {:ok, verdict} = Live.assay(request, request.player_bridges)
      assert verdict.furthest == ["beacon", "cairn"]
      assert Agent.get(counts, &Map.values/1) == [2]
    end

    test "a model that repeatedly names an invalid furthest pair fails with {:rejected, why}" do
      assayer(requests: 1, retries: 1)

      request = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"]
      }

      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["foggy coast", "beacon"])))
      end)

      assert {:error, {:rejected, why}} = Live.assay(request, request.bridges)
      assert why =~ "furthest"
    end

    test "prior Quips appear in user content of the grading prompt; system prompt and version are unchanged" do
      without = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        player_bridges: [
          %{player: "Jacob", bridge: "beacon"},
          %{player: "Melissa", bridge: "cairn"}
        ]
      }

      prior = [
        "Jacob brought the lighthouse, Melissa brought the dock.",
        "One of you packed the picnic, the other packed the ants."
      ]

      with_quips = Map.put(without, :prior_quips, prior)

      bare = Thereish.Steward.Assay.prompt(without, without.player_bridges)
      prompted = Thereish.Steward.Assay.prompt(with_quips, with_quips.player_bridges)

      assert Thereish.Steward.Assay.version() == "assay-4"
      assert prompted.system == bare.system
      refute prompted.user == bare.user

      for quip <- prior do
        assert prompted.user =~ quip
        refute bare.user =~ quip
      end

      assert prompted.user =~ ~r/constructions already used/i
    end

    test "prior Quips appear in user content of the fresh-Quip prompt; system prompt is unchanged" do
      without = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        player_bridges: [
          %{player: "Jacob", bridge: "beacon"},
          %{player: "Melissa", bridge: "cairn"}
        ]
      }

      prior = ["Jacob brought the lighthouse, Melissa brought the dock."]
      with_quips = Map.put(without, :prior_quips, prior)

      bare = Thereish.Steward.Assay.quip_prompt(without, without.player_bridges)
      prompted = Thereish.Steward.Assay.quip_prompt(with_quips, with_quips.player_bridges)

      assert prompted.system == bare.system
      assert prompted.schema_name == "quip"
      assert prompted.user =~ hd(prior)
      assert prompted.user =~ ~r/constructions already used/i
      refute bare.user =~ hd(prior)
    end

    test "quip_prompt carries Bookends, Bridges, earlier Attempts, and Gives" do
      request = %{
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        player_bridges: [
          %{player: "Jacob", bridge: "beacon"},
          %{player: "Melissa", bridge: "cairn"}
        ],
        earlier_attempts: [
          %{
            number: 1,
            bookends: ["pier", "quay"],
            bridges: [%{player: "Jacob", bridge: "jetty"}]
          }
        ],
        gives: [%{player: "Jacob", give: "foggy coast"}]
      }

      prompt = Thereish.Steward.Assay.quip_prompt(request, request.player_bridges)
      assert prompt.schema_name == "quip"
      assert prompt.user =~ "LANTERN and HARBOUR"
      assert prompt.user =~ "Jacob bridged with: beacon"
      assert prompt.user =~ "Melissa bridged with: cairn"
      assert prompt.user =~ "Jacob gave: foggy coast"
      assert prompt.user =~ "Attempt 1: Bookends: PIER and QUAY"
    end

    test "check_quip accepts non-empty quips and rejects blank or missing ones" do
      assert Thereish.Steward.Assay.check_quip(%{"quip" => "A good line."}) == :ok
      assert {:error, _} = Thereish.Steward.Assay.check_quip(%{"quip" => ""})
      assert {:error, _} = Thereish.Steward.Assay.check_quip(%{"quip" => "   "})
      assert {:error, _} = Thereish.Steward.Assay.check_quip(%{})
    end
  end

  describe "foley forge and rank via Live adapter" do
    test "forge with effects calls ElevenLabs" do
      Req.Test.stub(Thereish.Steward.ElevenLabs, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
        |> Plug.Conn.put_resp_header("character-cost", "100")
        |> Plug.Conn.send_resp(200, <<255, 251, 144, 100, 1>>)
      end)

      assert {:ok, candidates} = Live.forge(%{prompt: "beat", kind: :effects}, n: 2)
      assert length(candidates) == 2
      assert hd(candidates).bytes == <<255, 251, 144, 100, 1>>
    end

    test "forge with music calls Mureka" do
      Req.Test.stub(Thereish.Steward.Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_mureka_live"}))

          {"GET", "/v1/instrumental/query/task_mureka_live"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "id" => "task_mureka_live",
                "status" => "succeeded",
                "choices" => [%{"url" => "https://cdn.mureka.ai/track.mp3"}]
              })
            )

          {"GET", "/track.mp3"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.send_resp(200, <<255, 251, 144, 100, 2>>)
        end
      end)

      assert {:ok, candidates} = Live.forge(%{prompt: "house loop", kind: :music}, n: 1)
      assert length(candidates) == 1
      assert hd(candidates).bytes == <<255, 251, 144, 100, 2>>
    end

    test "rank calls Gemini ear" do
      clips = [<<1, 2, 3>>, <<4, 5, 6>>]

      Req.Test.stub(Thereish.Steward.Gemini, fn conn ->
        content =
          Jason.encode!(%{
            "ranking" => [
              %{"index" => 2, "reason" => "Better fit."},
              %{"index" => 1, "reason" => "Okay."}
            ]
          })

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "model" => "gemini-3.8-flash",
            "choices" => [%{"message" => %{"content" => content}}],
            "usage" => %{"prompt_tokens" => 50, "total_tokens" => 80}
          })
        )
      end)

      assert {:ok, ranking} = Live.rank(clips, "brief")
      assert Enum.map(ranking, & &1.index) == [2, 1]
    end
  end

  describe "answering later" do
    defp answer_later(call) do
      Thereish.Steward.answer_later(call, &{:answered, &1})
      assert_receive {:answered, answer}
      refute_receive {:answered, _}, 50
      answer
    end

    test "an ok answer comes back as it was" do
      assert answer_later(fn -> {:ok, :grade} end) == {:ok, :grade}
    end

    test "an error answer comes back as it was" do
      assert answer_later(fn -> {:error, :refused} end) == {:error, :refused}
    end

    test "a call that raises comes back as an error carrying the exception" do
      assert {:error, %RuntimeError{message: "boom"}} = answer_later(fn -> raise "boom" end)
    end

    test "a call that exits comes back as an exit error" do
      assert answer_later(fn -> exit(:gone) end) == {:error, {:exit, :gone}}
    end

    test "a call that throws comes back as a throw error" do
      assert answer_later(fn -> throw(:ball) end) == {:error, {:throw, :ball}}
    end
  end

  describe "the words for an Author failure" do
    test "each reason reads as the Game shows it" do
      for {reason, words} <- [
            {{:max_tokens, 4096}, "too broad or complex"},
            {:refused, "content declined"},
            {{:refusal, "not that"}, "declined: not that"},
            {%Req.TransportError{reason: :timeout}, "timed out"},
            {%{reason: :timeout}, "timed out"},
            {:timeout, "timed out"},
            {:unavailable, "unavailable"},
            {{:exit, :killed}, "process exited"},
            {%RuntimeError{message: "boom"}, "boom"},
            {"no Gives", "no Gives"},
            {:no_gives, "no_gives"},
            {{:http, 503}, "{:http, 503}"}
          ] do
        assert Thereish.Steward.author_failure(reason) == words
      end
    end
  end
end
