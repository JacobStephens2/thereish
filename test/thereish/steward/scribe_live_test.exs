defmodule Thereish.Steward.ScribeLiveTest do
  @moduledoc """
  The Scribe with a model behind it, and the two gates between the model and the
  Chronicle.

  Nobody is called: the provider is a recorded response, and what is under test
  is what the Steward does with what comes back.
  """
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  import Thereish.StewardFixtures

  alias Thereish.Steward

  defp page do
    %{
      bookends: ["lantern", "harbour"],
      melded: true,
      attempts: [
        %{
          number: 1,
          bookends: ["lantern", "harbour"],
          bridges: [
            %{seat_name: "Jacob", bridge: "cairn"},
            %{seat_name: "Melissa", bridge: "beacon"}
          ],
          verdicts: [%{band: "close", reasoning: "Two markers on one shore.", closeness: 62}]
        }
      ]
    }
  end

  # A Page the Room played before tonight, graded 91 and overruled to 88.
  defp earlier do
    %{
      bookends: ["candy", "cane"],
      gives: [],
      give: nil,
      melded: true,
      closeness: 91,
      attempts: [
        %{
          number: 1,
          bridges: [
            %{seat_name: "Jacob", bridge: "hook"},
            %{seat_name: "Melissa", bridge: "stripe"}
          ],
          verdicts: [
            %{
              bridges: ["hook", "stripe"],
              closeness: 91,
              band: "meld",
              reasoning: "Both are the shape of the thing."
            }
          ]
        }
      ],
      overrules: [
        %{
          proposer_name: "Melissa",
          couple_closeness: 88,
          couple_reasoning: "Close, not that close."
        }
      ],
      corrections: [],
      recap: %{recap: "Jacob wrote hook and Melissa wrote stripe.", callback: nil}
    }
  end

  defp answers(replies) do
    asked = Thereish.StewardFixtures.counts()

    recorded_scribe(fn conn, body ->
      turn = asked(asked, :recap)
      send(self(), {:asked, turn, body})

      Req.Test.json(conn, scribe_response(Enum.at(replies, turn - 1) || List.last(replies)))
    end)

    asked
  end

  describe "a recap the gates accept" do
    test "comes back as prose, a callback and its provenance" do
      live_scribe()
      answers([written_recap(callback: "They wrote cairn last month too.")])

      assert {:ok, recap} = Steward.recap(page(), [earlier()])

      assert recap.recap =~ "cairn"
      assert recap.callback == "They wrote cairn last month too."
      assert recap.meta.model == "claude-fable-5-1"
      assert recap.meta.prompt_version == "recap-3"
      assert recap.meta.attempts == 1
      assert recap.meta.cost_usd > 0
    end

    test "an empty callback is nothing rather than an empty string" do
      live_scribe()
      answers([written_recap(callback: "")])

      assert {:ok, %{callback: nil}} =
               Steward.recap(page(), [])
    end

    test "the configured effort reaches the provider request" do
      live_scribe()
      answers([written_recap(callback: "They wrote cairn last month too.")])

      assert {:ok, _recap} = Steward.recap(page(), [earlier()])
      assert_received {:asked, 1, body}
      assert body["output_config"]["effort"] == "low"
    end
  end

  describe "what the Scribe is told" do
    test "no earlier Page's closeness crosses in the request" do
      live_scribe()
      answers([written_recap(callback: "They wrote hook last month too.")])

      Steward.recap(page(), [earlier()])

      assert_received {:asked, 1, body}
      user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))

      assert user =~ ~s(Jacob bridged "hook")
      assert user =~ "Recap: Jacob wrote hook and Melissa wrote stripe."
      refute Jason.encode!(body) =~ "91"
      refute Jason.encode!(body) =~ "88"
      refute user =~ "closeness"
    end
  end

  describe "the Vale gate, and the one repair pass behind it" do
    test "prose the linter refuses is asked for again, with the rule quoted back" do
      live_scribe()

      counts =
        answers([
          written_recap(
            recap:
              "What a journey. Jacob wrote cairn and Melissa wrote beacon, a rich tapestry " <>
                "of an evening."
          ),
          written_recap(recap: ~s(Jacob wrote "cairn" and Melissa wrote "beacon".))
        ])

      assert {:ok, recap} = Steward.recap(page(), [])
      assert recap.recap == ~s(Jacob wrote "cairn" and Melissa wrote "beacon".)
      assert recap.meta.attempts == 2

      assert_received {:asked, 2, body}
      user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))

      assert user =~ "Scribe.Grandiose"
      assert user =~ "rejected"

      assert Agent.get(counts, &Map.get(&1, :recap)) == 2
    end

    test "prose that fails the repair pass too is no recap at all" do
      live_scribe()

      answers([
        written_recap(
          recap: "What a journey. Jacob wrote cairn, a rich tapestry of an evening indeed."
        )
      ])

      assert {:error, {:rejected, why}} =
               Steward.recap(page(), [])

      assert why =~ "Scribe.Grandiose"
    end

    test "one repair pass and no more" do
      live_scribe()
      counts = answers([written_recap(recap: "What a journey it was for cairn and beacon.")])

      assert {:error, _why} = Steward.recap(page(), [])
      assert Agent.get(counts, &Map.get(&1, :recap)) == 2
    end
  end

  describe "the check the linter cannot make" do
    test "a recap that names none of the players' words is refused" do
      live_scribe()

      answers([
        written_recap(recap: "A fine evening on the couch, and the two of them found each other.")
      ])

      assert {:error, {:rejected, why}} =
               Steward.recap(page(), [])

      assert why =~ "words the players wrote"
    end

    test "a recap that puts a number on the Page is refused" do
      live_scribe()
      answers([written_recap(recap: ~s(Jacob wrote "cairn" and it was worth every one of 62.))])

      assert {:error, {:rejected, why}} =
               Steward.recap(page(), [])

      assert why =~ "number"
    end
  end

  describe "a provider that does not answer" do
    test "is no recap rather than a crash" do
      live_scribe()

      recorded_scribe(fn conn, _body -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Steward.recap(page(), [])
    end
  end
end
