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
      assert html =~ "meld"
      refute html =~ "One mind"
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

    test "close band presents without flavour line" do
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
      assert html =~ "Different enough."
      refute html =~ "Passable"
      refute html =~ "Close enough."
    end

    test "the reveal renders Bridges, then the number and band, then the quip with no reasoning on screen",
         %{meld_room: room} do
      html = render_component(&reveal/1, room: room)

      # Order: Bridges -> Closeness/Band -> Quip
      {comp_idx, _} = :binary.match(html, ~s(data-role="comparison"))
      {close_idx, _} = :binary.match(html, ~s(data-role="closeness-display"))
      {quip_idx, _} = :binary.match(html, ~s(data-role="quip"))

      assert comp_idx < close_idx
      assert close_idx < quip_idx

      assert html =~ ~s(data-role="quip")
      assert html =~ "walk into a bar."
      refute html =~ ~s(data-role="reasoning")
      refute html =~ "The Assayer's reasoning"
      refute html =~ "They share 4 letters."
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

    test "the furthest apart line is removed on phone and stage", %{miss_room: room} do
      phone_html = render_component(&reveal/1, room: room, mode: :phone)
      stage_html = render_component(&reveal/1, room: room, mode: :stage)

      refute phone_html =~ ~s(data-role="furthest")
      refute phone_html =~ "Furthest apart"
      refute stage_html =~ ~s(data-role="furthest")
      refute stage_html =~ "Furthest apart"
    end

    test "the flavour line is removed on phone and stage", %{meld_room: room} do
      phone_html = render_component(&reveal/1, room: room, mode: :phone)
      stage_html = render_component(&reveal/1, room: room, mode: :stage)

      refute phone_html =~ "One mind"
      refute phone_html =~ "heads"
      refute stage_html =~ "One mind"
      refute stage_html =~ "heads"
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
