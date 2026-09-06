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

    test "author_writing displays reading settings initially and still writing when slow" do
      writing_room = %{
        phase: :writing,
        author_step: :writing
      }

      html = render_component(&author_writing/1, room: writing_room)
      assert html =~ "The Author is reading your settings..."
      assert html =~ ~s(data-role="beat-meter")
      assert html =~ ~s(data-step="writing")

      still_room = %{
        phase: :writing,
        author_step: :still_writing
      }

      html = render_component(&author_writing/1, room: still_room)
      assert html =~ "The Author is still writing..."
      assert html =~ ~s(data-step="still_writing")
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
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "cairo"}
          ],
          graded?: true,
          overruled?: false,
          quip: "\"cairn\" and \"cairo\" walk into a bar.",
          reasoning: "They share 4 letters.",
          furthest: [
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
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
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "beacon"}
          ],
          graded?: true,
          overruled?: false,
          quip: "\"cairn\" and \"beacon\" have never met.",
          reasoning: "Different roads entirely.",
          furthest: [
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
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
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
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
      assert html =~ "Melissa"
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
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "dock"}
          ],
          graded?: true,
          overruled?: false,
          quip: "Different enough.",
          reasoning: "Close enough.",
          furthest: [
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
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
      seat = %{id: "s1", name: "Melissa"}

      phone_html = render_component(&reveal/1, room: room, seat: seat, mode: :phone)
      stage_html = render_component(&reveal/1, room: room, seat: nil, mode: :stage)

      # Phone highlights your bridge
      assert phone_html =~ "(you)" or phone_html =~ ~s(data-you="true")

      # Stage is public theater
      assert stage_html =~ ~s(data-mode="stage")
      refute stage_html =~ ~s(data-you="true")
    end
  end

  describe "roster couples" do
    test "roster highlights couples with partner names" do
      room = %{
        seats: [
          %{
            id: "s1",
            name: "Melissa",
            you?: false,
            committed?: false,
            couple?: true,
            partner_id: "s2",
            partner_name: "Jacob"
          },
          %{
            id: "s2",
            name: "Jacob",
            you?: true,
            committed?: false,
            couple?: true,
            partner_id: "s1",
            partner_name: "Melissa"
          }
        ],
        open_seats: 0,
        seat_limit: 2,
        phase: :waiting
      }

      html = render_component(&roster/1, room: room)

      assert html =~ ~s(data-role="partner")
      assert html =~ "(with Jacob)"
      assert html =~ "(with Melissa)"
      assert html =~ ~s(data-couple="true")
    end
  end

  describe "couples on the reveal and stage meld map" do
    setup do
      pairs = [
        %{
          seat_ids: ["s1", "s2"],
          names: ["Melissa", "Jacob"],
          bridges: ["cairn", "cairo"],
          closeness: 80,
          band: :meld,
          melded?: true,
          couple?: true,
          cross_couple?: false,
          cross_couple_meld?: false,
          surprise: nil
        },
        %{
          seat_ids: ["s3", "s4"],
          names: ["Ada", "Ida"],
          bridges: ["wharf", "beacon"],
          closeness: 30,
          band: :miss,
          melded?: false,
          couple?: true,
          cross_couple?: false,
          cross_couple_meld?: false,
          surprise: nil
        },
        %{
          seat_ids: ["s1", "s4"],
          names: ["Melissa", "Ida"],
          bridges: ["cairn", "beacon"],
          closeness: 85,
          band: :meld,
          melded?: true,
          couple?: false,
          cross_couple?: true,
          cross_couple_meld?: true,
          surprise: "Melissa and Ida think alike"
        }
      ]

      room = %{
        phase: :reveal,
        reveal: %{
          closeness: 65,
          band: :close,
          melded?: false,
          bridges: [
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "cairo"},
            %{seat_id: "s3", name: "Ada", bridge: "wharf"},
            %{seat_id: "s4", name: "Ida", bridge: "beacon"}
          ],
          graded?: true,
          overruled?: false,
          quip: "All together now.",
          pairs: pairs
        }
      }

      %{room: room, pairs: pairs}
    end

    test "phone reveal puts player's own couple score first and marks cross-couple Melds", %{
      room: room
    } do
      melissa_seat = %{id: "s1", name: "Melissa"}
      html = render_component(&reveal/1, room: room, seat: melissa_seat, mode: :phone)

      # Displays own couple pair closeness
      assert html =~ ~s(data-role="own-couple-pair")
      assert html =~ ~s(data-role="couple-closeness")
      assert html =~ "Your couple: Melissa &amp; Jacob"
      assert html =~ "80"

      # Displays surprise cross-couple meld alert
      assert html =~ ~s(data-role="cross-couple-meld")
      assert html =~ "Melissa and Ida think alike"
    end

    test "stage reveal draws the meld map highlighting couples and cross-couple melds", %{
      room: room
    } do
      html = render_component(&reveal/1, room: room, mode: :stage)

      # Stage draws meld-map
      assert html =~ ~s(data-role="meld-map")
      assert html =~ "Meld Map"
      assert html =~ "3 pairs"

      # Couple badges
      assert html =~ ~s(data-role="couple-badge")
      assert html =~ "Couple"

      # Cross-couple meld alert
      assert html =~ ~s(data-role="cross-couple-meld")
      assert html =~ "Melissa and Ida think alike"
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

  describe "Sides: couple versus couple components" do
    test "roster renders sides grouping when in Sides mode" do
      room = %{
        seats: [
          %{id: "s1", name: "Melissa", you?: true, committed?: false},
          %{id: "s2", name: "Jacob", you?: false, committed?: false},
          %{id: "s3", name: "Ada", you?: false, committed?: false},
          %{id: "s4", name: "Sam", you?: false, committed?: false}
        ],
        seat_limit: 4,
        open_seats: 0,
        sides_mode?: true,
        sides: [
          %{
            id: :side_a,
            name: "Melissa & Jacob",
            you?: true,
            seat_ids: ["s1", "s2"],
            seats: [
              %{id: "s1", name: "Melissa", you?: true, committed?: false},
              %{id: "s2", name: "Jacob", you?: false, committed?: false}
            ]
          },
          %{
            id: :side_b,
            name: "Ada & Sam",
            you?: false,
            seat_ids: ["s3", "s4"],
            seats: [
              %{id: "s3", name: "Ada", you?: false, committed?: false},
              %{id: "s4", name: "Sam", you?: false, committed?: false}
            ]
          }
        ]
      }

      html = render_component(&roster/1, room: room)

      assert html =~ ~s(data-role="sides-roster")
      assert html =~ ~s(data-side="side_a")
      assert html =~ ~s(data-side="side_b")
      assert html =~ "Melissa &amp; Jacob"
      assert html =~ "Ada &amp; Sam"
      assert html =~ "(your side)"
      assert html =~ ~s(data-seat="s1")
      assert html =~ ~s(data-seat="s3")
    end

    test "reveal renders two side cards side by side with Closeness, bands, and badges" do
      room = %{
        phase: :reveal,
        reveal: %{
          mode: :sides,
          melded?: true,
          sides: [
            %{
              id: :side_a,
              name: "Melissa & Jacob",
              seat_ids: ["s1", "s2"],
              closer?: false,
              melded?: false,
              graded?: true,
              closeness: 82,
              band: :almost,
              quip: "Almost touching.",
              bridges: [
                %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
                %{seat_id: "s2", name: "Jacob", bridge: "cairo"}
              ]
            },
            %{
              id: :side_b,
              name: "Ada & Sam",
              seat_ids: ["s3", "s4"],
              closer?: true,
              melded?: true,
              graded?: true,
              closeness: 91,
              band: :meld,
              quip: "One mind in two heads.",
              bridges: [
                %{seat_id: "s3", name: "Ada", bridge: "beacon"},
                %{seat_id: "s4", name: "Sam", bridge: "lighthouse"}
              ]
            }
          ],
          bridges: [
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "cairo"},
            %{seat_id: "s3", name: "Ada", bridge: "beacon"},
            %{seat_id: "s4", name: "Sam", bridge: "lighthouse"}
          ],
          furthest: [
            %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
            %{seat_id: "s4", name: "Sam", bridge: "lighthouse"}
          ]
        }
      }

      seat = %{id: "s1", name: "Melissa"}
      html = render_component(&reveal/1, room: room, seat: seat, mode: :phone)

      assert html =~ ~s(data-role="sides-comparison")
      assert html =~ ~s(data-side="side_a")
      assert html =~ ~s(data-side="side_b")

      # Both scores appear
      assert html =~ "82"
      assert html =~ "91"
      assert html =~ "almost"
      assert html =~ "meld"

      # Badges
      assert html =~ ~s(data-role="closer-badge")
      assert html =~ ~s(data-role="melded-badge")

      # Quips
      assert html =~ "Almost touching."
      assert html =~ "One mind in two heads."

      # Fairness controls
      assert html =~ ~s(data-role="fairness-controls")
      assert html =~ "Was your Side's grade fair?"
    end

    test "overrule banner in Sides mode requires only partner agreement" do
      room = %{
        overrule: %{
          pending?: true,
          proposer_id: "s1",
          proposer_name: "Melissa",
          side_id: :side_a,
          your_side?: true,
          you_proposed?: false,
          you_agreed?: false,
          agreed_seat_ids: ["s1"]
        },
        reveal: %{mode: :sides, sides: []}
      }

      # Partner on the same side sees vote buttons
      partner_seat = %{id: "s2", name: "Jacob"}
      partner_html = render_component(&overrule_banner/1, room: room, seat: partner_seat)

      assert partner_html =~ ~s(data-role="overrule-vote")
      assert partner_html =~ "proposed overruling your Side&#39;s grade to a Meld"
      assert partner_html =~ ~s(data-role="agree-overrule")
      assert partner_html =~ ~s(data-role="decline-overrule")

      # Opponent on the other side sees information notice without vote buttons
      opposing_room = %{
        room
        | overrule: %{room.overrule | your_side?: false, you_proposed?: false, you_agreed?: false}
      }

      opponent_seat = %{id: "s3", name: "Ada"}
      opponent_html = render_component(&overrule_banner/1, room: opposing_room, seat: opponent_seat)

      refute opponent_html =~ ~s(data-role="overrule-vote")
      assert opponent_html =~ "proposed an overrule for their Side. Waiting for their partner to agree."
    end
  end
end
