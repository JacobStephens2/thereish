defmodule MeaningGameWeb.RoomComponentsTest do
  use MeaningGameWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import MeaningGameWeb.RoomComponents

  describe "assaying component (the beat)" do
    test "the 2.5s beat is visibly a beat, not a spinner" do
      room = %{
        phase: :assaying,
        assayer_step: :grading,
        provisional_band: nil
      }

      html = render_component(&assaying/1, room: room)

      # Maintains the data-role and data-step expected by escalation and rooms
      assert html =~ ~s(data-role="phase")
      assert html =~ ~s(data-step="grading")

      # Visibly a beat: includes a beat meter / cadence element
      assert html =~ ~s(data-role="beat-meter")

      # Not a spinner: must not use spinner classes or spinner elements
      refute html =~ "loading-spinner"
      refute html =~ "spinner"

      # Theatrical wording
      assert html =~ "Holding the breath" or html =~ "The beat" or html =~ "looking at them"
    end

    test "escalation beyond the beat displays the waiting narration" do
      slow_room = %{
        phase: :assaying,
        assayer_step: :slow
      }

      html = render_component(&assaying/1, room: slow_room)
      assert html =~ "The Assayer is still reading"
    end
  end

  describe "reveal component (the performance)" do
    setup do
      meld_room = %{
        phase: :reveal,
        reveal: %{
          closeness: 80,
          band: :meld,
          melded?: true,
          bridges: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "cairo"}
          ],
          graded?: true,
          overruled?: false,
          quip: "\"cairn\" and \"cairo\" walk into a bar.",
          reasoning: "They share 4 letters.",
          furthest: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "cairo"}
          ]
        }
      }

      miss_room = %{
        phase: :reveal,
        reveal: %{
          closeness: 24,
          band: :miss,
          melded?: false,
          bridges: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "beacon"}
          ],
          graded?: true,
          overruled?: false,
          quip: "\"cairn\" and \"beacon\" have never met.",
          reasoning: "Different roads entirely.",
          furthest: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "beacon"}
          ]
        }
      }

      no_verdict_room = %{
        phase: :reveal,
        reveal: %{
          closeness: nil,
          band: nil,
          melded?: false,
          bridges: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "beacon"}
          ],
          graded?: false,
          overruled?: false,
          quip: nil,
          reasoning: nil,
          furthest: nil
        }
      }

      %{meld_room: meld_room, miss_room: miss_room, no_verdict_room: no_verdict_room}
    end

    test "both Bridges land side-by-side with comparison reading first", %{meld_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="comparison")
      assert html =~ "cairn"
      assert html =~ "cairo"
      assert html =~ "Mara"
      assert html =~ "Jacob"
    end

    test "number arrives with climbing hook and band arrives with it", %{meld_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="closeness")
      assert html =~ "80"
      assert html =~ "ClimbNumber"
      assert html =~ ~s(data-role="band")
      assert html =~ "meld"
    end

    test "a Meld is staged as an arrival, distinct from a near miss", %{meld_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-arrival="meld")
      assert html =~ "One mind, two heads"
    end

    test "a harsh grade is staged as a shared joke, not a personal sting", %{miss_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-arrival="miss")
      assert html =~ "24"
      assert html =~ "miss"
      # Must not look like an error state / sting
      refute html =~ "alert-error"
      refute html =~ "text-error"
    end

    test "close band presents with passable fallback flavour" do
      close_room = %{
        phase: :reveal,
        reveal: %{
          closeness: 60,
          band: :close,
          melded?: false,
          bridges: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "dock"}
          ],
          graded?: true,
          overruled?: false,
          quip: "Different enough.",
          reasoning: "Close enough.",
          furthest: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "dock"}
          ]
        }
      }

      html = render_component(&reveal/1, room: close_room)

      assert html =~ ~s(data-arrival="close")
      assert html =~ "close"
      assert html =~ "Passable."
      assert html =~ "Different enough."
    end

    test "the quip reads as a punchline and reasoning is framed for argument", %{meld_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="quip")
      assert html =~ ~s(data-role="reasoning")
      assert html =~ "The Assayer's reasoning" or html =~ "The Assayer's case"
      assert html =~ "They share 4 letters."
    end

    test "the 10 second no-verdict path is staged as deliberate handover rather than broken", %{
      no_verdict_room: room
    } do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="no-verdict")
      assert html =~ "No verdict"
      assert html =~ "yours to call"
      assert html =~ "steps aside" or html =~ "handing over" or html =~ "yields"
    end

    test "the two furthest words are named, with whoever wrote them", %{miss_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="furthest")
      assert html =~ "cairn (Mara)"
      assert html =~ "beacon (Jacob)"
    end

    test "a table that wrote one word has no two ends to name", %{meld_room: room} do
      agreed =
        put_in(room.reveal.furthest, [
          %{seat_id: "s1", name: "Mara", bridge: "cairn"},
          %{seat_id: "s2", name: "Jacob", bridge: "cairn"}
        ])

      refute render_component(&reveal/1, room: agreed) =~ ~s(data-role="furthest")
    end

    test "the flavour counts the heads at the table", %{meld_room: room} do
      four =
        put_in(room.reveal.bridges, [
          %{seat_id: "s1", name: "Mara", bridge: "cairn"},
          %{seat_id: "s2", name: "Jacob", bridge: "cairo"},
          %{seat_id: "s3", name: "Ada", bridge: "cairns"},
          %{seat_id: "s4", name: "Ida", bridge: "cairo"}
        ])

      assert render_component(&reveal/1, room: four) =~ "One mind, four heads"
      assert render_component(&reveal/1, room: room) =~ "One mind, two heads"
    end

    test "stage and phone show complementary perspectives", %{meld_room: room} do
      seat = %{id: "s1", name: "Mara"}

      phone_html = render_component(&reveal/1, room: room, seat: seat, mode: :phone)
      stage_html = render_component(&reveal/1, room: room, seat: nil, mode: :stage)

      # Phone highlights your bridge
      assert phone_html =~ "(you)" or phone_html =~ ~s(data-you="true")

      # Stage is public theater
      assert stage_html =~ ~s(data-mode="stage")
      refute stage_html =~ ~s(data-you="true")
    end
  end

  describe "the carry line" do
    test "names the two words the next attempt will hang between" do
      room = %{phase: :reveal, next_bookends: ["cairn", "beacon"], next_bookends_chosen?: true}

      html = render_component(&carry_forward/1, room: room)

      assert html =~ ~s(data-role="carry-forward")
      assert html =~ "cairn and beacon"
      refute html =~ "nobody chose"
    end

    test "says when the Assayer did not choose them" do
      room = %{phase: :reveal, next_bookends: ["cairn", "beacon"], next_bookends_chosen?: false}

      html = render_component(&carry_forward/1, room: room)

      assert html =~ "cairn and beacon"
      assert html =~ "nobody chose"
    end
  end
end
