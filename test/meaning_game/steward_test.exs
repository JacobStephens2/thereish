defmodule MeaningGame.StewardTest do
  @moduledoc """
  The live Assayer, against recorded responses.

  Everything here asks the same question the couch asks — grade this Attempt's
  Bridges — and checks the things that are true of a grade whatever the model
  said: that both orderings were asked and both were kept, that a malformed
  answer was sent back rather than shown, that a hedged pair of requests was one
  question asked twice, and that a failure is a failure rather than a number.

  Nothing here asserts on what the Assayer is asked. The words of the question
  are going to move as the couple calibrate it, and a test that froze them would
  turn every calibration into a test failure. The one thing any of this compares
  is that two hedged requests are byte-identical to each other, which is a fact
  about hedging rather than about the wording.
  """
  # Which model answers, how often, and how patiently is application
  # configuration, and these tests move it.
  use MeaningGame.DataCase, async: false

  # A rejected answer is logged, and half of these tests reject one on purpose.
  @moduletag :capture_log

  import MeaningGame.StewardFixtures

  alias MeaningGame.Steward.Live

  @pair %{bookends: ["lantern", "harbour"], bridges: ["beacon", "cairn"]}

  # Which way round this request asked, named by the Bridge it put first.
  defp ordering(body), do: first_bridge(body, @pair.bridges)

  describe "grading a pair" do
    test "both orderings are graded, and both are kept beside the grade" do
      recorded(fn conn, body ->
        case ordering(body) do
          "beacon" -> Req.Test.json(conn, response(verdict(closeness: 80, reasoning: "Forward.")))
          "cairn" -> Req.Test.json(conn, response(verdict(closeness: 40, reasoning: "Reverse.")))
        end
      end)

      {:ok, verdict} = Live.assay(@pair)

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

      {:ok, verdict} = Live.assay(@pair)

      assert verdict.quip == "Both of you went looking for the shore."
      assert verdict.meta.model == "gemini-3.8-flash"
      assert verdict.meta.prompt_version == MeaningGame.Steward.Assay.version()
      # Two orderings, hedged two ways, and every token any of them spent.
      assert verdict.meta.cost_usd > 0
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

      assert {:ok, verdict} = Live.assay(@pair)
      assert verdict.closeness == 55
      assert Agent.get(counts, &Map.values/1) == [2, 2]
    end

    test "an answer that is not JSON at all is asked for again" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, ordering(body)) do
          1 -> Req.Test.json(conn, response("These two words are pretty close, I'd say."))
          _ -> Req.Test.json(conn, response(verdict(closeness: 55)))
        end
      end)

      assert {:ok, verdict} = Live.assay(@pair)
      assert verdict.closeness == 55
    end

    test "a model that never produces a valid answer is no verdict, not a crash" do
      assayer(requests: 1, retries: 1)

      recorded(fn conn, _body -> Req.Test.json(conn, response(verdict(closeness: 4000))) end)

      assert {:error, {:rejected, why}} = Live.assay(@pair)
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

      {:ok, verdict} = Live.assay(@pair)

      assert verdict.closeness == 80

      # Identical requests, not a race between two different questions: hedging
      # against a second question would make the grade a coin toss between two
      # distributions (design law 11).
      assert_receive {:asked, "beacon", first}
      assert_receive {:asked, "beacon", second}
      assert first == second
      assert_receive {:asked, "cairn", _}
      assert_receive {:asked, "cairn", _}
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

      assert {:error, {:http, 503, _body}} = Live.assay(@pair)
    end

    # A recorded response is served in this process rather than over a socket,
    # so what runs out here is the grading's whole budget rather than one
    # request's socket timeout. That is the one that has to hold: the escalation
    # ladder gives up at ten seconds, and it can only do that if the Steward has.
    test "a provider that never answers gives up before the game does" do
      assayer(requests: 1, retries: 0, deadline_ms: 50)

      recorded(fn conn, _body ->
        Process.sleep(5_000)
        Req.Test.json(conn, response(verdict()))
      end)

      assert {:error, :timeout} = Live.assay(@pair)
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

      {:ok, verdict} = Live.assay(@table)

      # Two orderings and not twenty-four: roster order against its reverse is
      # the same correction at four that it is at two.
      assert Agent.get(counts, &Map.values/1) == [1, 1]
      assert verdict.closeness == 50
      assert verdict.meta.forward == 60
      assert verdict.meta.reverse == 40
    end

    test "the two furthest words come from the forward ordering" do
      recorded(fn conn, body ->
        furthest =
          case table_ordering(body) do
            "beacon" -> ["beacon", "seagull"]
            "seagull" -> ["cairn", "lamp"]
          end

        Req.Test.json(conn, response(verdict(furthest: furthest)))
      end)

      {:ok, verdict} = Live.assay(@table)

      # The two orderings can name different pairs, and the next Attempt's
      # Bookends have to be one pair rather than an average of two.
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "the two furthest words come back as the players wrote them" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["  BEACON ", "Seagull"])))
      end)

      {:ok, verdict} = Live.assay(@table)

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

      assert {:ok, verdict} = Live.assay(@table)
      assert verdict.furthest == ["beacon", "seagull"]
      assert Agent.get(counts, &Map.values/1) == [2, 2]
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

      assert {:ok, verdict} = Live.assay(@table)
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "a model that never names two of the words is no verdict, not a guess" do
      assayer(requests: 1, retries: 1)

      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["beacon", "gull"])))
      end)

      assert {:error, {:rejected, why}} = Live.assay(@table)
      assert why =~ "furthest"
    end

    test "every ordering of the same four Bridges is one precedent" do
      assayer(requests: 1, retries: 0)
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, table_ordering(body))

        Req.Test.json(
          conn,
          response(verdict(closeness: 33, furthest: ["beacon", "seagull"]))
        )
      end)

      assert {:ok, _} = Live.assay(@table)
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      shuffled = %{@table | bridges: ["lamp", "seagull", "beacon", "cairn"]}

      assert {:ok, verdict} = Live.assay(shuffled)
      assert verdict.closeness == 33
      # The whole point of the cache: the same words meeting again get the same
      # grade, whatever order the Seats were filled in (design law 1).
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "a cached Verdict carries the two furthest words with it" do
      assayer(requests: 1, retries: 0)

      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(furthest: ["beacon", "seagull"])))
      end)

      assert {:ok, _} = Live.assay(@table)
      assert {:ok, cached} = Live.assay(@table)

      # A cache hit that lost the furthest pair would replay the grade but not
      # the game: those two words are the next Attempt's Bookends.
      assert cached.furthest == ["beacon", "seagull"]
    end
  end

  describe "the verdict cache is the precedent" do
    setup do
      assayer(requests: 1, retries: 0)
    end

    test "a repeated pair returns the stored verdict without calling the provider" do
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 77, reasoning: "First run.")))
      end)

      assert {:ok, verdict1} = Live.assay(@pair)
      assert verdict1.closeness == 77
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      # Subsequent call with the exact same pair skips provider entirely
      assert {:ok, verdict2} = Live.assay(@pair)
      assert verdict2.closeness == 77
      assert verdict2.reasoning == "First run."
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "the reverse ordering hits the same cached precedent" do
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 77, reasoning: "First run.")))
      end)

      assert {:ok, _} = Live.assay(@pair)
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      reversed = %{@pair | bridges: Enum.reverse(@pair.bridges)}
      assert {:ok, verdict} = Live.assay(reversed)
      assert verdict.closeness == 77
      assert verdict.reasoning == "First run."
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "a differing prompt version misses the cache and calls the provider" do
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 77, reasoning: "First run.")))
      end)

      assert {:ok, verdict1} = Live.assay(@pair)
      assert verdict1.closeness == 77
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      assayer(prompt_version: "a-different-question")

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 85, reasoning: "New prompt version.")))
      end)

      assert {:ok, verdict2} = Live.assay(@pair)
      assert verdict2.closeness == 85
      assert verdict2.reasoning == "New prompt version."
      assert Agent.get(counts, &Map.values/1) == [2, 2]
    end

    test "Steward.assay returns the cached precedent instantly" do
      assayer(adapter: MeaningGame.Steward.Live)

      recorded(fn conn, _body ->
        Req.Test.json(conn, response(verdict(closeness: 90, reasoning: "Instant.")))
      end)

      assert {:ok, verdict1} = MeaningGame.Steward.assay(@pair)
      assert verdict1.closeness == 90

      assert {:ok, verdict2} = MeaningGame.Steward.assay(@pair)
      assert verdict2.closeness == 90
      assert verdict2.reasoning == "Instant."
      assert verdict2.meta.latency_ms < 50
    end

    test "an overruled key returns the couple's ruling afterwards" do
      counts = counts()

      recorded(fn conn, body ->
        asked(counts, ordering(body))
        Req.Test.json(conn, response(verdict(closeness: 41, reasoning: "Original grade.")))
      end)

      assert {:ok, verdict1} = Live.assay(@pair)
      assert verdict1.closeness == 41
      assert Agent.get(counts, &Map.values/1) == [1, 1]

      couple_ruling = %{
        closeness: 100,
        reasoning: "Overruled jointly across all Seats. Recorded as precedent.",
        quip: "House law."
      }

      assert {:ok, _} =
               MeaningGame.Steward.overrule(
                 @pair.bookends,
                 @pair.bridges,
                 couple_ruling
               )

      assert {:ok, verdict2} = Live.assay(@pair)
      assert verdict2.closeness == 100
      assert verdict2.reasoning == "Overruled jointly across all Seats. Recorded as precedent."
      assert verdict2.quip == "House law."
      # Did not call the provider again!
      assert Agent.get(counts, &Map.values/1) == [1, 1]
    end

    test "Steward.overrule accepts a request map directly" do
      couple_ruling = %{
        closeness: 95,
        reasoning: "Overruled with request map.",
        quip: "Map ruling."
      }

      assert {:ok, _} = MeaningGame.Steward.overrule(@pair, couple_ruling)
      assert {:ok, verdict} = Live.assay(@pair)
      assert verdict.closeness == 95
      assert verdict.reasoning == "Overruled with request map."
    end
  end

  describe "foley forge and rank via Live adapter" do
    test "forge with effects calls ElevenLabs" do
      Req.Test.stub(MeaningGame.Steward.ElevenLabs, fn conn ->
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
      Req.Test.stub(MeaningGame.Steward.Mureka, fn conn ->
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

      Req.Test.stub(MeaningGame.Steward.Gemini, fn conn ->
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
end
