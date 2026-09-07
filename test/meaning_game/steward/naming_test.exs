defmodule MeaningGame.Steward.NamingTest do
  @moduledoc """
  The Scribe naming a Room with a real model behind it, against recorded responses.
  """
  use MeaningGame.DataCase, async: false

  @moduletag :capture_log

  import MeaningGame.StewardFixtures

  alias MeaningGame.Steward
  alias MeaningGame.Steward.Live

  @digests [
    """
    Page 1 (candy · cane) — Melded on attempt 2 (closeness: 88, meld)
      Attempt 2: Jacob bridged "hook", Mara bridged "hook". Verdict: 88 (meld)
    """
  ]

  defp naming_response(word, quip \\ nil) do
    data = if quip, do: %{"word" => word, "quip" => quip}, else: %{"word" => word}
    response(Jason.encode!(data))
  end

  defp live_naming(role_opts \\ []) do
    steward = Application.fetch_env!(:meaning_game, :steward)
    on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    naming = Keyword.merge(steward[:roles][:scribe][:jobs][:naming], role_opts)

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> put_in([:roles, :scribe, :api_key], "recorded-responses-need-no-key")
      |> put_in([:roles, :scribe, :jobs, :naming], naming)

    Application.put_env(:meaning_game, :steward, live)
  end

  describe "naming a Room" do
    setup do
      live_naming()
      :ok
    end

    test "a word the gate accepts comes back lowercase with quip" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, naming_response("CANE", "A nod to candy cane."))
      end)

      assert {:ok, %{word: "cane", quip: "A nod to candy cane."}} =
               Live.name_room(@digests, ["couch"])
    end

    test "the gate drops a 91-character quip in live naming without failing the word" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, naming_response("CANE", String.duplicate("a", 91)))
      end)

      assert {:ok, %{word: "cane", quip: nil}} = Live.name_room(@digests, ["couch"])
    end

    test "quip_code asks for a quip for a random word" do
      recorded(fn conn, body ->
        assert Enum.any?(body["messages"], fn m -> m["content"] =~ "CANE" end)
        Req.Test.json(conn, quip_response("A sweet four-letter room."))
      end)

      assert {:ok, "A sweet four-letter room."} = Live.quip_code("cane")
    end

    test "the gate rejects a word that is not four letters and retries once" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, :naming) do
          1 ->
            # 5-letter word
            Req.Test.json(conn, naming_response("CANDY"))

          2 ->
            # Repaired to 4 letters
            user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
            assert user =~ "not a four-letter word"
            Req.Test.json(conn, naming_response("CANE"))
        end
      end)

      assert {:ok, %{word: "cane"}} = Live.name_room(@digests, ["couch"])
      assert Agent.get(counts, &Map.get(&1, :naming)) == 2
    end

    test "the gate rejects a word not in the dictionary and retries once" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, :naming) do
          1 ->
            # Not in dictionary
            Req.Test.json(conn, naming_response("ZZQX"))

          2 ->
            user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
            assert user =~ "not in the dictionary"
            Req.Test.json(conn, naming_response("CANE"))
        end
      end)

      assert {:ok, %{word: "cane"}} = Live.name_room(@digests, ["couch"])
      assert Agent.get(counts, &Map.get(&1, :naming)) == 2
    end

    test "the gate rejects a profane word and retries once" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, :naming) do
          1 ->
            Req.Test.json(conn, naming_response("DAMN"))

          2 ->
            user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
            assert user =~ "profane"
            Req.Test.json(conn, naming_response("CANE"))
        end
      end)

      assert {:ok, %{word: "cane"}} = Live.name_room(@digests, ["couch"])
      assert Agent.get(counts, &Map.get(&1, :naming)) == 2
    end

    test "the gate rejects a taken Code and retries once" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, :naming) do
          1 ->
            # Already taken
            Req.Test.json(conn, naming_response("FLAK"))

          2 ->
            user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
            assert user =~ "already a Code"
            Req.Test.json(conn, naming_response("CANE"))
        end
      end)

      assert {:ok, %{word: "cane"}} = Live.name_room(@digests, ["flak"])
      assert Agent.get(counts, &Map.get(&1, :naming)) == 2
    end

    test "a word rejected twice returns an error" do
      counts = counts()

      recorded(fn conn, _body ->
        _turn = asked(counts, :naming)
        Req.Test.json(conn, naming_response("ZZQX"))
      end)

      assert {:error, {:rejected, why}} = Live.name_room(@digests, ["couch"])
      assert why =~ "not in the dictionary"
      assert Agent.get(counts, &Map.get(&1, :naming)) == 2
    end

    test "a model that times out past its deadline returns an error" do
      live_naming(deadline_ms: 20)

      recorded(fn conn, _body ->
        Process.sleep(50)
        Req.Test.json(conn, naming_response("CANE"))
      end)

      assert {:error, :timeout} = Steward.name_room(@digests, ["couch"])
    end

    test "a provider error is returned as error rather than crashing" do
      recorded(fn conn, _body ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, _reason} = Steward.name_room(@digests, ["couch"])
    end

    test "no history makes no model call and returns :no_history" do
      recorded(fn _conn, _body ->
        flunk("no history should make no model call")
      end)

      assert Steward.name_room([], ["couch"]) == {:error, :no_history}
    end

    test "the naming schema gains quip" do
      schema = MeaningGame.Steward.Naming.schema()
      # Schema contains quip property
      properties = schema.values |> List.keyfind("properties", 0) |> elem(1)
      assert List.keyfind(properties.values, "quip", 0) != nil
      assert List.keyfind(schema.values, "required", 0) == {"required", ["word"]}

      prompt = MeaningGame.Steward.Naming.prompt(@digests, ["couch"])
      assert prompt.system =~ "quip"
      assert prompt.user =~ "quip"
    end

    test "the gate accepts a non-empty single line of at most 90 characters" do
      valid = "A room that remembers yesterday."
      assert MeaningGame.Steward.Naming.quip(%{"quip" => valid}) == valid
    end

    test "the gate drops a 91-character quip without failing the word" do
      long_quip = String.duplicate("a", 91)
      json = %{"word" => "CANE", "quip" => long_quip}

      assert MeaningGame.Steward.Naming.check(json, ["couch"]) == :ok
      assert MeaningGame.Steward.Naming.quip(json) == nil
    end

    test "the gate drops a quip with a newline without failing the word" do
      newline_quip = "Line one\nLine two"
      json = %{"word" => "CANE", "quip" => newline_quip}

      assert MeaningGame.Steward.Naming.check(json, ["couch"]) == :ok
      assert MeaningGame.Steward.Naming.quip(json) == nil
    end

    test "the quip-only request has its own prompt and schema" do
      prompt = MeaningGame.Steward.Naming.quip_prompt("cane")
      assert prompt.schema_name == "room_quip"
      assert prompt.user =~ "CANE"

      schema = MeaningGame.Steward.Naming.quip_schema()
      properties = schema.values |> List.keyfind("properties", 0) |> elem(1)
      assert List.keyfind(properties.values, "quip", 0) != nil
    end
  end
end
