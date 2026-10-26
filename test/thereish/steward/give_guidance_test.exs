defmodule Thereish.Steward.GiveGuidanceTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  import Thereish.StewardFixtures

  alias Thereish.Steward

  defp guidance_settings(opts) do
    steward = Application.fetch_env!(:thereish, :steward)
    job = Keyword.merge(steward[:roles][:scribe][:jobs][:guidance], opts)

    Application.put_env(
      :thereish,
      :steward,
      put_in(steward, [:roles, :scribe, :jobs, :guidance], job)
    )
  end

  setup do
    steward = Application.fetch_env!(:thereish, :steward)
    on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)
    Application.put_env(:thereish, :steward, Keyword.put(steward, :adapter, Steward.Live))
    :ok
  end

  test "the Scribe gets closed Page words and the previous invitation, without grades" do
    chronicle = [
      %{
        bookends: ["lantern", "harbour"],
        gives: [%{seat_name: "Mara", text: "first snow"}],
        melded: false,
        closeness: 97.412,
        attempts: [],
        overrules: [],
        corrections: []
      }
    ]

    recorded(fn conn, body ->
      user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
      assert user =~ "first snow"
      assert user =~ "lantern"
      assert user =~ "Give an old idea a new coat."
      refute user =~ "97.412"

      Req.Test.json(
        conn,
        response(Jason.encode!(%{text: "Give a sound or a memory: crunch · thaw · homecoming."}))
      )
    end)

    assert {:ok, %{text: "Give a sound or a memory: crunch · thaw · homecoming.", meta: meta}} =
             Steward.give_guidance(chronicle, "Give an old idea a new coat.")

    assert meta.cost_usd > 0
  end

  test "a Room without Pages gets a fresh invitation without invented history" do
    recorded(fn conn, body ->
      user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
      assert user =~ "Nothing yet; this is the first Page."

      Req.Test.json(
        conn,
        response(
          Jason.encode!(%{text: "Give a mood or a memory: wistful · a loose end · first snow."})
        )
      )
    end)

    assert {:ok, %{text: "Give a mood or a memory: wistful · a loose end · first snow."}} =
             Steward.give_guidance([])
  end

  test "a repeated invitation is rejected and repaired before it reaches a Seat" do
    previous = "Give a feeling: restless · homesick · jubilant."
    fresh = "Give a sound or an idea: kettle song · a loose end · midnight blue."

    recorded(fn conn, body ->
      user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
      text = if user =~ "rejected by the validator", do: fresh, else: previous
      Req.Test.json(conn, response(Jason.encode!(%{text: text})))
    end)

    assert {:ok, %{text: ^fresh, meta: %{attempts: 2}}} = Steward.give_guidance([], previous)
  end

  test "blank and oversized answers leave a usable invitation that differs from the old one" do
    previous = "Give a feeling: restless · homesick · jubilant."

    for invalid <- ["   ", String.duplicate("x", 301)] do
      recorded(fn conn, _body ->
        Req.Test.json(conn, response(Jason.encode!(%{text: invalid})))
      end)

      assert {:ok, %{text: text, meta: %{fallback: true}}} = Steward.give_guidance([], previous)
      assert String.trim(text) != ""
      assert String.length(text) <= 300
      refute text == previous
    end
  end

  test "prose rejected by the Scribe's Vale gate never reaches a Seat" do
    rejected = "Give an idea! A memory, a feeling, or a sound: thaw · homesick · brass bands."
    assert {:error, faults} = Steward.Vale.check(rejected)
    assert faults =~ "Scribe.Exclaim"
    guidance_settings(retries: 0)

    recorded(fn conn, _body ->
      Req.Test.json(conn, response(Jason.encode!(%{text: rejected})))
    end)

    assert {:ok, %{text: text, meta: %{fallback: true}}} = Steward.give_guidance([])
    refute text == rejected
  end

  test "the Scribe repairs a Vale fault using the normal repair pass" do
    rejected = "Give an idea! A memory, a feeling, or a sound: thaw · homesick · brass bands."
    repaired = "Give an idea or a memory: thaw · homesick · brass bands."

    recorded(fn conn, body ->
      user = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
      text = if user =~ "Scribe.Exclaim", do: repaired, else: rejected
      Req.Test.json(conn, response(Jason.encode!(%{text: text})))
    end)

    assert {:ok, %{text: ^repaired, meta: %{attempts: 2}}} = Steward.give_guidance([])
  end

  test "missing credentials return guidance without making a provider request" do
    guidance_settings(api_key: nil)

    recorded(fn _conn, _body ->
      flunk("guidance must not call a provider without credentials")
    end)

    assert {:ok, %{text: text, meta: %{fallback: true}}} = Steward.give_guidance([])
    assert text =~ "Give"
  end

  test "a slow or crashed Scribe returns fallback guidance" do
    steward = Application.fetch_env!(:thereish, :steward)
    Application.put_env(:thereish, :steward, Keyword.put(steward, :adapter, Steward.Fake))
    guidance_settings(deadline_ms: 20)

    for fake <- [[guidance_delay_ms: 100], [guidance_mode: :raise]] do
      current = Application.fetch_env!(:thereish, :steward)
      Application.put_env(:thereish, :steward, Keyword.put(current, :fake, fake))
      assert {:ok, %{text: text, meta: %{fallback: true}}} = Steward.give_guidance([])
      assert text =~ "Give"
    end
  end
end
