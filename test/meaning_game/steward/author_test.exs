defmodule MeaningGame.Steward.AuthorTest do
  use MeaningGame.DataCase, async: false

  @moduletag :capture_log

  import MeaningGame.StewardFixtures

  alias MeaningGame.Steward
  alias MeaningGame.Steward.Author

  describe "schema validation" do
    test "accepts a well-formed Author response" do
      json = Jason.decode!(authored_page_json())
      assert :ok = Author.check_schema(json)
      assert :ok = Author.check(json)
    end

    test "rejects missing required fields" do
      json = Jason.decode!(authored_page_json()) |> Map.delete("bait")
      assert {:error, _why} = Author.check_schema(json)
    end

    test "rejects fewer than two bookends" do
      json = Jason.decode!(authored_page_json(bookends: ["single"]))
      assert {:error, _why} = Author.check(json)
    end

    test "rejects fewer than two deep bridges" do
      json = Jason.decode!(authored_page_json(deep_bridges: ["one"]))
      assert {:error, _why} = Author.check(json)
    end

    test "rejects missing band scripts" do
      json =
        authored_page_json(
          band_scripts: %{
            "miss" => "miss",
            "adjacent" => "adj",
            "close" => "close",
            "meld" => "meld"
          }
        )
        |> Jason.decode!()

      assert {:error, _why} = Author.check_schema(json)
    end

    test "rejects old band scripts keyed on near" do
      json =
        authored_page_json(
          band_scripts: %{
            "miss" => "miss",
            "adjacent" => "adj",
            "near" => "near",
            "meld" => "meld",
            "deep_meld" => "deep"
          }
        )
        |> Jason.decode!()

      assert {:error, _why} = Author.check_schema(json)
    end

    test "prompts and pages carry bumped prompt_version author-2" do
      assert Author.version() == "author-2"
    end
  end

  describe "legality checking on Author output" do
    test "rejects when bookends share a root" do
      json = Jason.decode!(authored_page_json(bookends: ["run", "running"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "share a root"
    end

    test "rejects when bait shares root with a bookend" do
      json = Jason.decode!(authored_page_json(bookends: ["garden", "house"], bait: "gardening"))
      assert {:error, why} = Author.check(json)
      assert why =~ "shares a root"
    end

    test "rejects when a bridge is not in the dictionary" do
      json = Jason.decode!(authored_page_json(bait: "xyzzyq"))
      assert {:error, why} = Author.check(json)
      assert why =~ "not in the dictionary"
    end

    test "rejects when deep bridge is missing from likely_bridges" do
      json =
        Jason.decode!(
          authored_page_json(deep_bridges: ["lawnmower", "chores"], likely_bridges: ["lawnmower"])
        )

      assert {:error, why} = Author.check(json)
      assert why =~ "likely_bridges"
    end
  end

  describe "live authoring against recorded responses" do
    setup do
      steward = Application.fetch_env!(:meaning_game, :steward)
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      Application.put_env(
        :meaning_game,
        :steward,
        Keyword.put(steward, :adapter, MeaningGame.Steward.Live)
      )

      :ok
    end

    test "rejects illegal clue and regenerates with feedback against recorded responses" do
      agent = counts()

      recorded_author(fn conn, body ->
        call_num = asked(agent, "author")

        case call_num do
          1 ->
            # First attempt produces an illegal clue: bait shares root with bookend
            illegal = authored_page_json(bookends: ["flower", "soil"], bait: "flowering")
            Req.Test.json(conn, author_response(illegal))

          2 ->
            # Second attempt receives rejection feedback and produces legal clue
            [%{"content" => user_prompt}] =
              Enum.filter(body["messages"], &(&1["role"] == "user"))

            assert user_prompt =~ "Your previous answer was rejected by the validator"
            assert user_prompt =~ "shares a root"

            legal =
              authored_page_json(
                bookends: ["flower", "soil"],
                bait: "petal",
                deep_bridges: ["growth", "seed"],
                likely_bridges: ["petal", "growth", "seed"]
              )

            Req.Test.json(conn, author_response(legal))
        end
      end)

      assert {:ok, page} = Steward.author("botany")
      assert page.meta.attempts == 2
      assert page.bait == "petal"
      assert page.bookends == ["flower", "soil"]
      assert page.meta.model == "claude-fable-5-1"
      assert is_float(page.meta.cost_usd) and page.meta.cost_usd > 0
    end

    test "a token-cap overrun is terminal for that Page and is never retried" do
      agent = counts()

      recorded_author(fn conn, _body ->
        call_num = asked(agent, "author")
        assert call_num == 1
        Req.Test.json(conn, author_response("{}", stop_reason: "max_tokens"))
      end)

      assert {:error, {:max_tokens, _}} = Steward.author("huge chapter")
      # Ensure it did NOT retry
      assert Agent.get(agent, &Map.get(&1, "author", 0)) == 1
    end
  end
end
