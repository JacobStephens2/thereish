defmodule MeaningGame.ScribeTest do
  @moduledoc """
  The Scribe writing the Chronicle after play.

  Every Page here is played through the Room, because the thing worth pinning is
  that a Page closing gets a paragraph written about it — not that a function
  called with the right map inserts a row.
  """
  use MeaningGame.DataCase, async: false

  import MeaningGame.RoomFixtures

  alias MeaningGame.Chronicle
  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Room
  alias MeaningGame.Steward

  setup do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, melissa: melissa, jacob: jacob}
  end

  defp play(ctx, melissa_bridge, jacob_bridge) do
    :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, melissa_bridge)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

    await_reveal(ctx.slug)
  end

  defp room_id(slug), do: Repo.get_by!(Room, slug: slug).id

  # The Scribe runs in a task the Room does not wait for, which is the whole
  # point of it, so a test that wants the paragraph waits the way the Chronicle
  # page does.
  defp await_recap(slug) do
    eventually(
      fn ->
        case Chronicle.recaps(room_id(slug)) do
          [] -> false
          recaps -> List.last(recaps)
        end
      end,
      "the Scribe never wrote a recap for #{slug}"
    )
  end

  describe "a closed Page gets a recap" do
    test "written into the Chronicle as its own event", ctx do
      play(ctx, "cairn", "cairo")

      recap = await_recap(ctx.slug)

      assert recap.recap =~ "cairn"
      assert recap.room_id == room_id(ctx.slug)
      assert recap.model == "fake-scribe"
      assert recap.prompt_version == "fake-recap-1"
    end

    test "attached to the Page it is about", ctx do
      play(ctx, "cairn", "cairo")

      recap = await_recap(ctx.slug)
      [page] = Chronicle.pages(room_id(ctx.slug))

      assert recap.page_id == page.id
    end

    test "with nothing to reach back to on the Room's first Page", ctx do
      play(ctx, "cairn", "cairo")

      assert await_recap(ctx.slug).callback == nil
    end

    test "and a callback once the Room has a Chronicle behind it", ctx do
      play(ctx, "cairn", "cairo")
      await_recap(ctx.slug)

      :ok = Rooms.next_page(ctx.slug, ctx.melissa.id)
      play(ctx, "mirage", "mirages")

      assert eventually(
               fn ->
                 case Chronicle.recaps(room_id(ctx.slug)) do
                   [_first, second] -> second
                   _not_yet -> false
                 end
               end,
               "the Scribe never wrote a second recap"
             ).callback == "They have been here before."
    end
  end

  describe "a Scribe that cannot write" do
    test "leaves the Page without a recap rather than taking the Room down", ctx do
      steward(recap_mode: :unavailable)

      play(ctx, "cairn", "cairo")
      await_scribe()

      assert [_page] = Chronicle.pages(room_id(ctx.slug))
      assert Chronicle.recaps(room_id(ctx.slug)) == []
      assert Rooms.snapshot(ctx.slug, nil).reveal != nil
    end

    test "falling over is not a Page lost either", ctx do
      steward(recap_mode: :raise)

      play(ctx, "cairn", "cairo")
      await_scribe()

      assert [_page] = Chronicle.pages(room_id(ctx.slug))
      assert Chronicle.recaps(room_id(ctx.slug)) == []
    end

    test "the Room does not wait for the paragraph", ctx do
      # A Scribe slower than the whole reveal. The couple see their grade
      # regardless, which is what running it in a task buys.
      steward(recap_delay_ms: 400)

      view = play(ctx, "cairn", "cairo")

      assert view.reveal != nil
      assert Chronicle.recaps(room_id(ctx.slug)) == []
      assert await_recap(ctx.slug)
    end
  end

  describe "the book" do
    test "shows the recap on the Page it was written about", ctx do
      play(ctx, "cairn", "cairo")
      await_recap(ctx.slug)

      assert [page] = Chronicle.book(ctx.slug)
      assert page.recap.recap =~ "cairn"
      assert page.recap.corrected? == false
    end

    test "says nothing where the Scribe wrote nothing", ctx do
      steward(recap_mode: :unavailable)
      play(ctx, "cairn", "cairo")
      await_scribe()

      assert [page] = Chronicle.book(ctx.slug)
      assert page.recap == nil
    end

    test "reads the players' correction over the Scribe's paragraph", ctx do
      play(ctx, "cairn", "cairo")
      recap = await_recap(ctx.slug)
      [stored] = Chronicle.pages(room_id(ctx.slug))

      {:ok, _} =
        Chronicle.record_correction(room_id(ctx.slug), %{
          page_id: stored.id,
          seat_id: ctx.melissa.id,
          target: "recap",
          original_value: recap.recap,
          corrected_value: "We both wrote cairn, near enough."
        })

      assert [page] = Chronicle.book(ctx.slug)
      assert page.recap.recap == "We both wrote cairn, near enough."
      assert page.recap.original_recap == recap.recap
      assert page.recap.corrected? == true
    end

    test "keeps the paragraph the couple were shown when the Scribe runs again", ctx do
      play(ctx, "cairn", "cairo")
      first = await_recap(ctx.slug)
      [stored] = Chronicle.pages(room_id(ctx.slug))

      {:ok, _} =
        Chronicle.record_recap(room_id(ctx.slug), %{
          page_id: stored.id,
          recap: "A second run at the same evening, with cairn in it.",
          callback: nil
        })

      assert [page] = Chronicle.book(ctx.slug)
      assert page.recap.recap == "A second run at the same evening, with cairn in it."
      assert [^first, _second] = Chronicle.recaps(room_id(ctx.slug))
    end
  end

  describe "what the Scribe reads and what the Author does not" do
    test "the Scribe's digest carries the recaps it has already written", ctx do
      play(ctx, "cairn", "cairo")
      recap = await_recap(ctx.slug)

      assert Chronicle.scribe_digest(room_id(ctx.slug)) =~ recap.recap
    end

    test "the Author's digest does not", ctx do
      play(ctx, "cairn", "cairo")
      recap = await_recap(ctx.slug)

      refute Chronicle.digest(room_id(ctx.slug)) =~ recap.recap
    end
  end

  describe "the Markdown export" do
    test "carries the recap and round-trips it", ctx do
      play(ctx, "cairn", "cairo")
      recap = await_recap(ctx.slug)

      markdown = Chronicle.to_markdown(ctx.slug)
      assert markdown =~ "> " <> recap.recap

      assert {:ok, [page]} = Chronicle.from_markdown(markdown)
      assert page.recap.recap == recap.recap
    end

    test "carries the callback beside it", ctx do
      play(ctx, "cairn", "cairo")
      await_recap(ctx.slug)
      :ok = Rooms.next_page(ctx.slug, ctx.melissa.id)
      play(ctx, "mirage", "mirages")
      await_scribe()

      assert {:ok, [_first, second]} =
               Chronicle.from_markdown(Chronicle.to_markdown(ctx.slug))

      assert second.recap.callback == "They have been here before."
    end

    test "a recap that wrapped over several lines comes back whole", ctx do
      play(ctx, "cairn", "cairo")
      await_recap(ctx.slug)
      [stored] = Chronicle.pages(room_id(ctx.slug))

      {:ok, _} =
        Chronicle.record_recap(room_id(ctx.slug), %{
          page_id: stored.id,
          recap: "They both wrote cairn.\nNeither would say why.",
          callback: "Like the candy cane."
        })

      assert {:ok, [page]} = Chronicle.from_markdown(Chronicle.to_markdown(ctx.slug))
      assert page.recap.recap == "They both wrote cairn.\nNeither would say why."
      assert page.recap.callback == "Like the candy cane."
    end

    test "a Page with no recap exports without one", ctx do
      steward(recap_mode: :unavailable)
      play(ctx, "cairn", "cairo")
      await_scribe()

      assert {:ok, [page]} = Chronicle.from_markdown(Chronicle.to_markdown(ctx.slug))
      assert page.recap == nil
    end
  end

  describe "what the Scribe is allowed to see" do
    test "the Page it is handed carries bands and words and no number" do
      page = %{
        id: "page-1",
        anchors: ["lantern", "harbour"],
        melded: true,
        closeness: 88,
        attempts: [
          %{
            number: 1,
            anchors: ["lantern", "harbour"],
            closeness: 88,
            bridges: [
              %{seat_name: "Jacob", bridge: "keeper", seat_id: "a", corrected?: false},
              %{seat_name: "Melissa", bridge: "guide", seat_id: "b", corrected?: false}
            ],
            verdicts: [
              %{band: "meld", reasoning: "One shore.", closeness: 88, quip: "Ha.", forward: 90}
            ]
          }
        ]
      }

      readable = MeaningGame.Steward.Recap.readable(page)

      # Everything the Scribe writes from, and not one number anywhere in it.
      assert readable.attempts |> hd() |> Map.get(:bridges) |> hd() |> Map.get(:bridge) ==
               "keeper"

      assert readable.attempts |> hd() |> Map.get(:verdicts) |> hd() |> Map.get(:band) == "meld"

      refute readable |> inspect() |> String.contains?("88")
      refute readable |> inspect() |> String.contains?("closeness")
    end
  end

  describe "the role behind the seam" do
    test "the Scribe's recap job is configured with a model of its own" do
      assert %{model: "claude-fable-5-1", provider: MeaningGame.Steward.Anthropic} =
               Steward.role(:scribe, :recap)
    end

    test "a job inherits what the role says and overrides what it names" do
      role = Steward.role(:scribe, :recap)

      # `retries` is the role's and `max_tokens` is the job's.
      assert role.retries == 1
      assert role.max_tokens == 8_000
      refute Map.has_key?(role, :jobs)
    end
  end
end
