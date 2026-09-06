defmodule MeaningGameWeb.SpendLiveTest do
  use MeaningGameWeb.ConnCase, async: false

  import MeaningGame.RoomFixtures
  import Phoenix.LiveViewTest

  alias MeaningGame.Chronicle
  alias MeaningGame.Repo
  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Room

  describe "operator spend page (/spend)" do
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
      assert totals_text =~ "$0.0047"
      assert totals_text =~ "6 calls"
      assert totals_text =~ "2 unpriced"

      # By role section
      role_text = render(element(view, "[data-role=spend-by-role]"))
      assert role_text =~ "Author"
      assert role_text =~ "Assayer"
      assert role_text =~ "Scribe"
      assert role_text =~ "Foley"

      # By model section
      model_text = render(element(view, "[data-role=spend-by-model]"))
      assert model_text =~ "gemini-3.8-flash"
      assert model_text =~ "claude-fable-5-1"
      assert model_text =~ "octave-2"

      # By role and model section
      role_model_text = render(element(view, "[data-role=spend-by-role-and-model]"))
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
      assert rooms_text =~ "$0.0047"
      assert rooms_text =~ "$0.0000"
    end
  end
end
