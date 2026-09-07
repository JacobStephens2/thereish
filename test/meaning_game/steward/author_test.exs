defmodule MeaningGame.Steward.AuthorTest do
  use MeaningGame.DataCase, async: false

  @moduletag :capture_log

  import MeaningGame.StewardFixtures

  alias MeaningGame.Steward
  alias MeaningGame.Steward.Author

  describe "schema validation" do
    test "accepts a well-formed Author response" do
      json = Jason.decode!(author_json())
      assert :ok = Author.check_schema(json)
      assert :ok = Author.check(json)
    end

    test "rejects missing required fields" do
      json = Jason.decode!(author_json()) |> Map.delete("why")
      assert {:error, _why} = Author.check_schema(json)

      json2 = Jason.decode!(author_json()) |> Map.delete("bookends")
      assert {:error, _why} = Author.check_schema(json2)
    end

    test "rejects bookends not being a list of two" do
      json = Jason.decode!(author_json(bookends: ["single"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "exactly two items"

      json3 = Jason.decode!(author_json(bookends: ["one", "two", "three"]))
      assert {:error, why} = Author.check(json3)
      assert why =~ "exactly two items"
    end

    test "prompts and pages carry bumped prompt_version author-3" do
      assert Author.version() == "author-3"
    end
  end

  describe "legality checking on Author output" do
    test "rejects when bookends share a root" do
      json = Jason.decode!(author_json(bookends: ["run", "running"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "share a root"
    end

    test "rejects when bookend shares root with a give word" do
      json = Jason.decode!(author_json(bookends: ["castle", "ocean"]))
      gives = [%{seat_id: "s1", name: "Alice", text: "an ancient castle in the woods"}]

      assert {:error, why} = Author.check(json, gives)
      assert why =~ "shares a root with setting word"
    end

    test "rejects when bookend exceeds 20 characters" do
      json = Jason.decode!(author_json(bookends: ["supercalifragilisticexpialidocious", "tree"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "exceeds 20 characters"
    end

    test "rejects when bookend is more than two words" do
      json = Jason.decode!(author_json(bookends: ["one two three", "four"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "must be one or two words"
    end

    test "rejects when bookend contains disallowed punctuation or numbers" do
      json = Jason.decode!(author_json(bookends: ["word#1", "second"]))
      assert {:error, why} = Author.check(json)
      assert why =~ "letters, hyphens or apostrophes only"
    end

    test "accepts legal one- or two-word bookends with hyphens or apostrophes" do
      json = Jason.decode!(author_json(bookends: ["polar-bear", "don't-know"]))
      assert :ok = Author.check(json)
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

    test "rejects illegal bookend and regenerates with feedback against recorded responses" do
      agent = counts()

      gives = [
        %{seat_id: "s1", name: "Alice", text: "walking along the beach"},
        %{seat_id: "s2", name: "Bob", text: "deep inside the forest"}
      ]

      recorded_author(fn conn, body ->
        call_num = asked(agent, "author")

        case call_num do
          1 ->
            # First attempt produces a bookend sharing a root with give ("beach")
            illegal = author_json(bookends: ["beach", "tree"])
            Req.Test.json(conn, author_response(illegal))

          2 ->
            # Second attempt receives rejection feedback and produces legal bookends
            [%{"content" => user_prompt}] =
              Enum.filter(body["messages"], &(&1["role"] == "user"))

            assert user_prompt =~ "Your previous answer was rejected by the validator"
            assert user_prompt =~ "shares a root"

            legal = author_json(bookends: ["ocean", "woods"])
            Req.Test.json(conn, author_response(legal))
        end
      end)

      assert {:ok, result} = Steward.author(%{gives: gives})
      assert result.meta.attempts == 2
      assert result.bookends == ["ocean", "woods"]
      assert result.meta.model == "gemini-3.8-flash"
      assert is_float(result.meta.cost_usd) and result.meta.cost_usd > 0
    end

    test "rejects if retries are spent without a valid response" do
      agent = counts()
      gives = [%{seat_id: "s1", name: "Alice", text: "walking along the beach"}]

      recorded_author(fn conn, _body ->
        _call_num = asked(agent, "author")
        # Always illegal
        illegal = author_json(bookends: ["beach", "shore"])
        Req.Test.json(conn, author_response(illegal))
      end)

      assert {:error, {:rejected, why}} = Steward.author(%{gives: gives})
      assert why =~ "shares a root"
      # retries: 1 means 1 initial ask + 1 retry = 2 attempts total
      assert Agent.get(agent, &Map.get(&1, "author", 0)) == 2
    end

    test "author role has flash and astra jobs with matching budgets and distinct providers" do
      flash_role = Steward.role(:author, :flash)
      astra_role = Steward.role(:author, :astra)

      assert flash_role.provider == MeaningGame.Steward.Gemini
      assert flash_role.model == "gemini-3.8-flash"
      assert flash_role.effort == "low"
      assert flash_role.max_tokens == 400
      assert flash_role.timeout_ms == 8_000
      assert flash_role.deadline_ms == 8_000

      assert astra_role.provider == MeaningGame.Steward.OpenAI
      assert astra_role.model == "gpt-6-astra"
      assert astra_role.effort == "low"
      assert astra_role.max_tokens == 400
      assert astra_role.timeout_ms == 8_000
      assert astra_role.deadline_ms == 8_000
    end

    test "Steward writes with the job named by the Page's arm" do
      gives = [
        %{seat_id: "s1", name: "Alice", text: "walking along the beach"},
        %{seat_id: "s2", name: "Bob", text: "deep inside the forest"}
      ]

      recorded_author(fn conn, _body ->
        Req.Test.json(conn, author_response(author_json(bookends: ["ocean", "woods"])))
      end)

      assert {:ok, flash_res} = Steward.author(%{gives: gives}, job: :flash)
      assert flash_res.meta.arm == :flash
      assert flash_res.meta.model == "gemini-3.8-flash"

      Req.Test.stub(MeaningGame.Steward.OpenAI, fn conn ->
        response_body = %{
          "object" => "chat.completion",
          "created" => 1_756_000_000,
          "model" => "gpt-6-astra",
          "choices" => [
            %{
              "index" => 0,
              "finish_reason" => "stop",
              "message" => %{
                "role" => "assistant",
                "content" => author_json(bookends: ["beacon", "haven"])
              }
            }
          ],
          "usage" => %{
            "prompt_tokens" => 200,
            "completion_tokens" => 50,
            "total_tokens" => 250
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response_body))
      end)

      assert {:ok, astra_res} = Steward.author(%{gives: gives}, job: :astra)
      assert astra_res.meta.arm == :astra
      assert astra_res.meta.model == "gpt-6-astra"
      assert astra_res.bookends == ["beacon", "haven"]
    end
  end
end
