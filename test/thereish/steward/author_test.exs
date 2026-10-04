defmodule Thereish.Steward.AuthorTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  import Thereish.StewardFixtures

  alias Thereish.Steward
  alias Thereish.Steward.Author

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
      assert why =~ "exactly 2 items"

      json3 = Jason.decode!(author_json(bookends: ["one", "two", "three"]))
      assert {:error, why} = Author.check(json3)
      assert why =~ "exactly 2 items"
    end

    test "prompts and pages carry bumped prompt_version author-4" do
      assert Author.version() == "author-4"
    end
  end

  describe "the count of Bookends the Author was asked for" do
    @four_gives [
      %{name: "Melissa", text: "a candlelit cathedral"},
      %{name: "Jacob", text: "a cyberpunk nightclub"},
      %{name: "Ada", text: "a deep sea trench"},
      %{name: "Sam", text: "a vintage bookstore"}
    ]

    test "accepts exactly the count asked for" do
      json =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "abyss", "folio"],
            from: ["Melissa", "Jacob", "Ada", "Sam"]
          )
        )

      assert :ok = Author.check(json, @four_gives, 4)
    end

    test "rejects one more or fewer than the count asked for" do
      four =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "abyss", "folio"],
            from: ["Melissa", "Jacob", "Ada", "Sam"]
          )
        )

      assert {:error, too_few} = Author.check(four, @four_gives, 6)
      assert too_few =~ "exactly 6 items"

      three =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "abyss"],
            from: ["Melissa", "Jacob", "Ada"]
          )
        )

      assert {:error, too_few_for_four} = Author.check(three, @four_gives, 4)
      assert too_few_for_four =~ "exactly 4 items"

      five =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "abyss", "folio", "ember"],
            from: ["Melissa", "Jacob", "Ada", "Sam", "Melissa"]
          )
        )

      assert {:error, too_many} = Author.check(five, @four_gives, 4)
      assert too_many =~ "exactly 4 items"
    end

    test "at a Full table rejects two Bookends from the same Give" do
      json =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "abyss", "folio"],
            from: ["Melissa", "Jacob", "Melissa", "Sam"]
          )
        )

      assert {:error, why} = Author.check(json, @four_gives, 4)
      assert why =~ "same setting"
    end

    test "root rules hold across N Bookends" do
      shared =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "folio", "folios"],
            from: ["Melissa", "Jacob", "Ada", "Sam"]
          )
        )

      assert {:error, shared_why} = Author.check(shared, @four_gives, 4)
      assert shared_why =~ "share a root"

      with_give =
        Jason.decode!(
          author_json(
            bookends: ["nave", "neon", "abyss", "folio"],
            from: ["Melissa", "Jacob", "Ada", "Sam"]
          )
        )

      gives = [
        %{name: "Melissa", text: "a candlelit cathedral"},
        %{name: "Jacob", text: "a cyberpunk nightclub"},
        %{name: "Ada", text: "an abyssal trench"},
        %{name: "Sam", text: "a vintage bookstore"}
      ]

      assert {:error, give_why} = Author.check(with_give, gives, 4)
      assert give_why =~ "shares a root with setting word"
    end
  end

  describe "the Author brief names the count and the rule" do
    @four_gives [
      %{name: "Melissa", text: "a candlelit cathedral"},
      %{name: "Jacob", text: "a cyberpunk nightclub"},
      %{name: "Ada", text: "a deep sea trench"},
      %{name: "Sam", text: "a vintage bookstore"}
    ]

    test "a Full table brief asks for one Bookend from each setting's world" do
      prompt = Author.prompt(@four_gives, nil, 4)
      combined = prompt.system <> "\n" <> prompt.user

      assert combined =~ "Exactly 4"
      assert combined =~ "Full table"
      assert combined =~ "one Bookend from each"
    end

    test "a two-Bookend brief asks for two Bookends from two different settings" do
      prompt = Author.prompt(@four_gives, nil, 2)
      combined = prompt.system <> "\n" <> prompt.user

      assert combined =~ "Exactly 2"
      assert combined =~ "not a Full table"
      refute combined =~ "one Bookend from each"
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
      steward = Application.fetch_env!(:thereish, :steward)
      on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(steward, :adapter, Thereish.Steward.Live)
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
            illegal = author_json(bookends: ["beach", "tree"], from: ["Alice", "Bob"])
            Req.Test.json(conn, author_response(illegal))

          2 ->
            # Second attempt receives rejection feedback and produces legal bookends
            [%{"content" => user_prompt}] =
              Enum.filter(body["messages"], &(&1["role"] == "user"))

            assert user_prompt =~ "Your previous answer was rejected by the validator"
            assert user_prompt =~ "shares a root"

            legal = author_json(bookends: ["ocean", "woods"], from: ["Alice", "Bob"])
            Req.Test.json(conn, author_response(legal))
        end
      end)

      assert {:ok, result} = Steward.author(%{gives: gives})
      assert result.meta.attempts == 2
      assert result.bookends == ["ocean", "woods"]
      assert result.meta.model == "gemini-3.8-flash"
      assert is_float(result.meta.cost_usd) and result.meta.cost_usd > 0
    end

    test "reads the Room's Page views as the Author's digest" do
      gives = [
        %{seat_id: "s1", name: "Alice", text: "walking along the beach"},
        %{seat_id: "s2", name: "Bob", text: "deep inside the forest"}
      ]

      test = self()

      recorded_author(fn conn, body ->
        [%{"content" => user_prompt}] = Enum.filter(body["messages"], &(&1["role"] == "user"))
        send(test, {:asked, user_prompt})

        legal = author_json(bookends: ["ocean", "woods"], from: ["Alice", "Bob"])
        Req.Test.json(conn, author_response(legal))
      end)

      chronicle = [
        %{
          bookends: ["candy", "cane"],
          gives: [],
          give: nil,
          melded: true,
          closeness: 88,
          attempts: [
            %{
              number: 1,
              bridges: [%{seat_name: "Alice", bridge: "hook"}],
              verdicts: [%{bridges: ["hook"], closeness: 88, band: "meld", reasoning: nil}]
            }
          ],
          overrules: [],
          corrections: [],
          recap: %{recap: "Alice wrote hook.", callback: nil}
        }
      ]

      assert {:ok, _result} = Steward.author(%{gives: gives}, chronicle: chronicle)
      assert_received {:asked, prompt}
      assert prompt =~ "Chronicle digest:\n" <> Thereish.Steward.Digest.author(chronicle)
      refute prompt =~ "Alice wrote hook."

      assert {:ok, _result} = Steward.author(%{gives: gives}, chronicle: [])
      assert_received {:asked, prompt}
      assert prompt =~ "Chronicle digest:\nNothing yet; this is the first Page."
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

      assert flash_role.provider == Thereish.Steward.Gemini
      assert flash_role.model == "gemini-3.8-flash"
      assert flash_role.effort == "low"
      assert flash_role.max_tokens == 400
      assert flash_role.timeout_ms == 8_000
      assert flash_role.deadline_ms == 8_000

      assert astra_role.provider == Thereish.Steward.OpenAI
      assert astra_role.model == "gpt-6-astra"
      assert astra_role.effort == "low"
      assert astra_role.max_tokens == 400
      assert astra_role.timeout_ms == 8_000
      assert astra_role.deadline_ms == 8_000
    end

    test "the A/B harness passes the count through and its records carry it" do
      gives = [
        %{seat_id: "s1", name: "Melissa", text: "a candlelit cathedral"},
        %{seat_id: "s2", name: "Jacob", text: "a cyberpunk nightclub"},
        %{seat_id: "s3", name: "Ada", text: "a deep sea trench"},
        %{seat_id: "s4", name: "Sam", text: "a vintage bookstore"}
      ]

      recorded_author(fn conn, body ->
        [%{"content" => user_prompt}] =
          Enum.filter(body["messages"], &(&1["role"] == "user"))

        [%{"content" => system_prompt}] =
          Enum.filter(body["messages"], &(&1["role"] == "system"))

        combined = system_prompt <> "\n" <> user_prompt
        assert combined =~ "Exactly 4"
        assert combined =~ "Full table"
        assert combined =~ "one Bookend from each"

        Req.Test.json(
          conn,
          author_response(
            author_json(
              bookends: ["nave", "neon", "abyss", "folio"],
              from: ["Melissa", "Jacob", "Ada", "Sam"]
            )
          )
        )
      end)

      assert {:ok, result} = Steward.author(%{gives: gives, count: 4}, job: :flash)
      assert result.bookends == ["nave", "neon", "abyss", "folio"]
      assert result.meta.count == 4
      assert result.meta.arm == :flash
      assert result.meta.prompt_version == "author-4"
    end

    test "Steward writes with the job named by the Page's arm" do
      gives = [
        %{seat_id: "s1", name: "Alice", text: "walking along the beach"},
        %{seat_id: "s2", name: "Bob", text: "deep inside the forest"}
      ]

      recorded_author(fn conn, _body ->
        Req.Test.json(
          conn,
          author_response(author_json(bookends: ["ocean", "woods"], from: ["Alice", "Bob"]))
        )
      end)

      assert {:ok, flash_res} = Steward.author(%{gives: gives}, job: :flash)
      assert flash_res.meta.arm == :flash
      assert flash_res.meta.model == "gemini-3.8-flash"

      Req.Test.stub(Thereish.Steward.OpenAI, fn conn ->
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
                "content" => author_json(bookends: ["beacon", "haven"], from: ["Alice", "Bob"])
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
