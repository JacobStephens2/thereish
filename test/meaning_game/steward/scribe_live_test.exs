defmodule MeaningGame.Steward.ScribeLiveTest do
  @moduledoc """
  The Scribe with a model behind it, and the two gates between the model and the
  Chronicle.

  Nobody is called: the provider is a recorded response, and what is under test
  is what the Steward does with what comes back.
  """
  use MeaningGame.DataCase, async: false

  @moduletag :capture_log

  import MeaningGame.StewardFixtures

  alias MeaningGame.Steward

  defp page do
    %{
      anchors: ["lantern", "harbour"],
      melded: true,
      attempts: [
        %{
          number: 1,
          anchors: ["lantern", "harbour"],
          bridges: [
            %{seat_name: "Jacob", bridge: "cairn"},
            %{seat_name: "Melissa", bridge: "beacon"}
          ],
          verdicts: [%{band: "close", reasoning: "Two markers on one shore.", closeness: 62}]
        }
      ]
    }
  end

  defp answers(replies) do
    asked = MeaningGame.StewardFixtures.counts()

    recorded_author(fn conn, body ->
      turn = asked(asked, :recap)
      send(self(), {:asked, turn, body})

      Req.Test.json(conn, author_response(Enum.at(replies, turn - 1) || List.last(replies)))
    end)

    asked
  end

  describe "a recap the gates accept" do
    test "comes back as prose, a callback and its provenance" do
      live_scribe()
      answers([written_recap(callback: "They wrote cairn last month too.")])

      assert {:ok, recap} = Steward.recap(page(), "Page 1 (candy · cane) — Melded on attempt 2")

      assert recap.recap =~ "cairn"
      assert recap.callback == "They wrote cairn last month too."
      assert recap.meta.model == "claude-fable-5-1"
      assert recap.meta.prompt_version == "recap-2"
      assert recap.meta.attempts == 1
      assert recap.meta.cost_usd > 0
    end

    test "an empty callback is nothing rather than an empty string" do
      live_scribe()
      answers([written_recap(callback: "")])

      assert {:ok, %{callback: nil}} =
               Steward.recap(page(), "Nothing yet; this is the first Page.")
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

      assert {:ok, recap} = Steward.recap(page(), "Nothing yet; this is the first Page.")
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
               Steward.recap(page(), "Nothing yet; this is the first Page.")

      assert why =~ "Scribe.Grandiose"
    end

    test "one repair pass and no more" do
      live_scribe()
      counts = answers([written_recap(recap: "What a journey it was for cairn and beacon.")])

      assert {:error, _why} = Steward.recap(page(), "Nothing yet; this is the first Page.")
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
               Steward.recap(page(), "Nothing yet; this is the first Page.")

      assert why =~ "words the players wrote"
    end

    test "a recap that puts a number on the Page is refused" do
      live_scribe()
      answers([written_recap(recap: ~s(Jacob wrote "cairn" and it was worth every one of 62.))])

      assert {:error, {:rejected, why}} =
               Steward.recap(page(), "Nothing yet; this is the first Page.")

      assert why =~ "number"
    end
  end

  describe "a provider that does not answer" do
    test "is no recap rather than a crash" do
      live_scribe()

      recorded_author(fn conn, _body -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Steward.recap(page(), "Nothing yet; this is the first Page.")
    end
  end
end
