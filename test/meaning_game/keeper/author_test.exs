defmodule MeaningGame.Keeper.AuthorTest do
  use MeaningGame.DataCase, async: false

  @moduletag :capture_log

  import MeaningGame.KeeperFixtures

  alias MeaningGame.Keeper
  alias MeaningGame.Keeper.Author

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

    test "rejects fewer than two anchors" do
      json = Jason.decode!(authored_page_json(anchors: ["single"]))
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
            "near" => "near",
            "meld" => "meld"
          }
        )
        |> Jason.decode!()

      assert {:error, _why} = Author.check_schema(json)
    end
  end

  describe "legality checking on Author output" do
    test "rejects when anchors share a root" do
      json = Jason.decode!(authored_page_json(anchors: ["run", "running"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "share a root"
    end

    test "rejects when bait shares root with an anchor" do
      json = Jason.decode!(authored_page_json(anchors: ["garden", "house"], bait: "gardening"))
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
      keeper = Application.fetch_env!(:meaning_game, :keeper)
      on_exit(fn -> Application.put_env(:meaning_game, :keeper, keeper) end)

      Application.put_env(
        :meaning_game,
        :keeper,
        Keyword.put(keeper, :adapter, MeaningGame.Keeper.Live)
      )

      :ok
    end

    test "rejects illegal clue and regenerates with feedback against recorded responses" do
      agent = counts()

      recorded_author(fn conn, body ->
        call_num = asked(agent, "author")

        case call_num do
          1 ->
            # First attempt produces an illegal clue: bait shares root with anchor
            illegal = authored_page_json(anchors: ["flower", "soil"], bait: "flowering")
            Req.Test.json(conn, author_response(illegal))

          2 ->
            # Second attempt receives rejection feedback and produces legal clue
            [%{"content" => user_prompt}] =
              Enum.filter(body["messages"], &(&1["role"] == "user"))

            assert user_prompt =~ "Your previous answer was rejected by the validator"
            assert user_prompt =~ "shares a root"

            legal =
              authored_page_json(
                anchors: ["flower", "soil"],
                bait: "petal",
                deep_bridges: ["growth", "seed"],
                likely_bridges: ["petal", "growth", "seed"]
              )

            Req.Test.json(conn, author_response(legal))
        end
      end)

      assert {:ok, page} = Keeper.author("botany")
      assert page.meta.attempts == 2
      assert page.bait == "petal"
      assert page.anchors == ["flower", "soil"]
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

      assert {:error, {:max_tokens, _}} = Keeper.author("huge chapter")
      # Ensure it did NOT retry
      assert Agent.get(agent, &Map.get(&1, "author", 0)) == 1
    end
  end
end
