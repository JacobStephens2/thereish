defmodule ThereishWeb.SpendLiveTest do
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Rooms
  alias Thereish.Rooms.Room

  describe "operator spend page (/spend)" do
    setup %{conn: conn} do
      %{conn: log_in_admin(conn)}
    end

    test "renders noindex header and empty state when no rooms exist", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/spend")

      assert html =~ ~r/<meta[^>]*robots[^>]*noindex/i
      assert has_element?(view, "[data-role=spend-heading]")
      assert render(element(view, "[data-role=spend-heading]")) =~ "Spend"
      assert has_element?(view, "[data-role=spend-totals]")
    end

    test "renders all-Rooms totals, by role, by model, and per-Room breakdown", %{conn: conn} do
      slug1 = open_room()
      room1 = Repo.get_by!(Room, slug: slug1)
      {:ok, mara} = Rooms.join(slug1, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug1, "Jacob", device_token())

      now = DateTime.utc_now()

      entry1 = %{
        document: %{"bookends" => ["desert", "oasis"]},
        author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
        music_meta: %{provider: "mureka", model: "mureka-v1", cost_usd: 0.0400},
        closed_because: :meld,
        melded?: true,
        closeness: 90,
        attempts: [
          %{
            number: 1,
            bookends: ["desert", "oasis"],
            closeness: 90,
            melded?: true,
            bridges: [
              %{seat_id: mara.id, bridge: "water"},
              %{seat_id: jacob.id, bridge: "water"}
            ],
            verdicts: [
              %{
                seat_ids: [mara.id, jacob.id],
                bridges: ["water", "water"],
                graded?: true,
                closeness: 90,
                band: :meld,
                reasoning: "Both said water.",
                quip: "Water in the sand.",
                meta: %{model: "gemini-3.8-flash", cost_usd: 0.0010},
                voice_meta: %{
                  model: "octave-2",
                  cost_usd: 0.0005,
                  provider: "hume",
                  voice: "dungeon-master",
                  latency_ms: 450
                }
              }
            ]
          }
        ]
      }

      {:ok, page1} = Chronicle.write(room1.id, entry1, now)

      {:ok, _recap1} =
        Chronicle.record_recap(room1.id, %{
          page_id: page1.id,
          recap: "A trek through dunes to an oasis.",
          model: "claude-fable-5-1",
          cost_usd: 0.0030
        })

      # Create second room with unpriced calls
      slug2 = open_room()
      room2 = Repo.get_by!(Room, slug: slug2)
      {:ok, alice} = Rooms.join(slug2, "Alice", device_token())
      {:ok, bob} = Rooms.join(slug2, "Bob", device_token())

      entry2 = %{
        document: %{"bookends" => ["sun", "moon"]},
        author_meta: %{model: "gemini-3.8-flash", cost_usd: nil},
        closed_because: :meld,
        melded?: true,
        closeness: 90,
        attempts: [
          %{
            number: 1,
            bookends: ["sun", "moon"],
            closeness: 90,
            melded?: true,
            bridges: [
              %{seat_id: alice.id, bridge: "sky"},
              %{seat_id: bob.id, bridge: "sky"}
            ],
            verdicts: [
              %{
                seat_ids: [alice.id, bob.id],
                bridges: ["sky", "sky"],
                graded?: false,
                closeness: nil,
                band: nil,
                reasoning: nil,
                quip: nil,
                meta: %{model: "gemini-3.8-flash", cost_usd: nil}
              }
            ]
          }
        ]
      }

      {:ok, _page2} = Chronicle.write(room2.id, entry2, now)

      {:ok, view, _html} = live(conn, ~p"/spend")

      # Totals
      totals_text = render(element(view, "[data-role=spend-totals]"))
      assert totals_text =~ "$0.0447"
      assert totals_text =~ "7 calls"
      assert totals_text =~ "2 unpriced"

      # By role section
      role_text = render(element(view, "[data-role=spend-by-role]"))
      assert role_text =~ "Author"
      assert role_text =~ "Assayer"
      assert role_text =~ "Scribe"
      assert role_text =~ "Foley"
      assert role_text =~ "$0.0405"

      # By model section
      model_text = render(element(view, "[data-role=spend-by-model]"))
      assert model_text =~ "gemini-3.8-flash"
      assert model_text =~ "claude-fable-5-1"
      assert model_text =~ "mureka-v1"
      assert model_text =~ "octave-2"

      # By role and model section
      role_model_text = render(element(view, "[data-role=spend-by-role-and-model]"))
      assert role_model_text =~ "Foley"
      assert role_model_text =~ "mureka-v1"
      assert role_model_text =~ "$0.0400"
      assert role_model_text =~ "Scribe"
      assert role_model_text =~ "claude-fable-5-1"
      assert role_model_text =~ "$0.0030"
      assert role_model_text =~ "Foley"
      assert role_model_text =~ "octave-2"
      assert role_model_text =~ "$0.0005"

      # Per-room breakdown
      rooms_text = render(element(view, "[data-role=spend-by-room]"))
      assert rooms_text =~ slug1
      assert rooms_text =~ slug2
      assert has_element?(view, "a[href='/r/#{slug1}/chronicle.md']", "Markdown")
      assert has_element?(view, "a[href='/r/#{slug1}/calibration.json']", "Calibration")
      assert rooms_text =~ "$0.0447"
      assert rooms_text =~ "$0.0000"
      assert rooms_text =~ "Opened"
      opened1 = Calendar.strftime(room1.inserted_at, "%b %d, %Y")
      opened2 = Calendar.strftime(room2.inserted_at, "%b %d, %Y")
      assert has_element?(view, "[data-role=room-opened]", opened1)
      assert has_element?(view, "[data-role=room-opened]", opened2)
    end

    test "shows in-play sentence when Pages are in play, and omits it when count is zero", %{
      conn: conn
    } do
      # When no rooms are in play (count = 0)
      {:ok, view, html} = live(conn, ~p"/spend")
      refute html =~ "not yet counted"
      refute has_element?(view, "[data-role=in-play-count]")

      # When 1 room is in play (in bridging)
      slug1 = open_room()
      {:ok, mara} = Rooms.join(slug1, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug1, "Jacob", device_token())
      :ok = Rooms.give(slug1, mara.id, "setting one")
      :ok = Rooms.give(slug1, jacob.id, "setting two")
      await_phase(slug1, :bridging)

      {:ok, view1, html1} = live(conn, ~p"/spend")
      assert html1 =~ "1 Page in play, not yet counted"
      assert has_element?(view1, "[data-role=in-play-count]")

      assert render(element(view1, "[data-role=in-play-count]")) =~
               "1 Page in play, not yet counted"

      # When 2 rooms are in play
      slug2 = open_room()
      {:ok, alice} = Rooms.join(slug2, "Alice", device_token())
      {:ok, bob} = Rooms.join(slug2, "Bob", device_token())
      :ok = Rooms.give(slug2, alice.id, "theme one")
      :ok = Rooms.give(slug2, bob.id, "theme two")
      await_phase(slug2, :bridging)

      {:ok, view2, html2} = live(conn, ~p"/spend")
      assert html2 =~ "2 Pages in play, not yet counted"
      assert has_element?(view2, "[data-role=in-play-count]")

      assert render(element(view2, "[data-role=in-play-count]")) =~
               "2 Pages in play, not yet counted"
    end
  end
end
