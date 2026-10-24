defmodule ThereishWeb.RoomComponentsTest do
  use ThereishWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import ThereishWeb.RoomComponents

  alias Thereish.Mask

  describe "seat_mask (a Seat's Mask on every Room screen)" do
    defp seat(mask, overrides \\ %{}) do
      Map.merge(%{id: "s1", name: "Mara", colour: "#e11d48", mask: mask}, overrides)
    end

    test "a drawn Mask is the picture, named for its Seat" do
      mask = %Mask{url: "/media/masks/mask-mara.png", meta: %{}}
      html = render_component(&seat_mask/1, seat: seat(mask), size: :lg)

      assert html =~ ~s(data-role="seat-mask")
      assert html =~ ~s(src="/media/masks/mask-mara.png")
      assert html =~ ~s(alt="Mara")
      refute html =~ "mask-face-down"
      refute html =~ "seat-colour-dot"
    end

    test "face down is the card, marked with its Seat and wearing its colour" do
      html = render_component(&seat_mask/1, seat: seat(:face_down), size: :md)

      assert html =~ ~s(data-role="mask-face-down")
      assert html =~ ~s(data-seat="s1")
      assert html =~ ~s(title="Mask face down")
      assert html =~ "🂠"
      assert html =~ "--seat-color: #e11d48"
      refute html =~ "seat-mask"
      refute html =~ "seat-colour-dot"
    end

    test ":dot is the colour dot, hidden from screen readers" do
      html = render_component(&seat_mask/1, seat: seat(:dot), size: :sm)

      assert html =~ ~s(data-role="seat-colour-dot")
      assert html =~ ~s(aria-hidden="true")
      assert html =~ "#e11d48"
      refute html =~ "seat-mask"
      refute html =~ "mask-face-down"
    end

    test "no Mask yet draws the same dot as :dot" do
      assert render_component(&seat_mask/1, seat: seat(nil), size: :sm) ==
               render_component(&seat_mask/1, seat: seat(:dot), size: :sm)
    end

    test "a Mask without a URL draws the dot" do
      html =
        render_component(&seat_mask/1, seat: seat(%Mask{url: nil, meta: %{}}), size: :sm)

      assert html =~ ~s(data-role="seat-colour-dot")
    end

    test "a Seat with no colour falls back to the primary colour" do
      for mask <- [:face_down, :dot] do
        html = render_component(&seat_mask/1, seat: seat(mask, %{colour: nil}), size: :md)
        assert html =~ "var(--color-primary, currentColor)"
      end
    end

    test "at a badge size the dot is bare" do
      html = render_component(&seat_mask/1, seat: seat(:dot), size: :xs)

      assert html =~ ~r/\A\s*<span[^>]*data-role="seat-colour-dot"/
    end

    test "from :md up the dot sits in a tile the size of a picture" do
      mask = %Mask{url: "/media/masks/mask-mara.png", meta: %{}}

      for size <- [:md, :lg] do
        dot = render_component(&seat_mask/1, seat: seat(:dot), size: size)
        picture = render_component(&seat_mask/1, seat: seat(mask), size: size)
        face_down = render_component(&seat_mask/1, seat: seat(:face_down), size: size)

        refute dot =~ ~r/\A\s*<span[^>]*data-role="seat-colour-dot"/
        assert dot =~ ~s(data-role="seat-colour-dot")

        square = square_class(picture)
        assert square == square_class(dot)
        assert square == square_class(face_down)
      end
    end

    test "at :xl the picture fills the square and the dot stays bare" do
      mask = %Mask{url: "/media/masks/mask-mara.png", meta: %{}}

      assert render_component(&seat_mask/1, seat: seat(mask), size: :xl) =~ "size-24"

      assert render_component(&seat_mask/1, seat: seat(:dot), size: :xl) =~
               ~r/\A\s*<span[^>]*data-role="seat-colour-dot"/
    end

    # The size class of the outermost element.
    defp square_class(html) do
      [_, class] = Regex.run(~r/\A\s*<\w+[^>]*class="([^"]*)"/, html)
      [size] = Regex.run(~r/\bsize-\d+\b/, class)
      size
    end
  end

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
      assert html =~ "The Author is reading your Gives..."
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

    test "number, band, cards and marker are performed by one sequencer", %{meld_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="closeness")
      assert html =~ "80"
      assert html =~ "RevealSequence"
      assert html =~ ~s(data-role="band")
      assert html =~ "meld"
      refute html =~ "ClimbNumber"
    end

    test "the reveal carries the numbers the hold was armed with", %{meld_room: room} do
      html = render_component(&reveal/1, room: room)
      sequence = Application.fetch_env!(:thereish, :reveal_sequence_ms)

      assert html =~ ~s(data-stagger="#{sequence[:stagger]}")
      assert html =~ ~s(data-cap="#{sequence[:cap]}")
      assert html =~ ~s(data-settle="#{sequence[:settle]}")
    end

    test "the closeness card wears its band, and three near misses wear three", %{miss_room: room} do
      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="closeness-display")
      assert html =~ ~s(data-band="miss")

      bands =
        for {closeness, band} <- [{24, :miss}, {40, :adjacent}, {60, :close}] do
          reveal = %{room.reveal | closeness: closeness, band: band}
          html = render_component(&reveal/1, room: %{room | reveal: reveal})

          assert html =~ ~s(data-band="#{band}")

          band
        end

      assert bands == Enum.uniq(bands)
    end

    test "the Rail is drawn on the phone, on the Stage and on a quiet phone", %{miss_room: room} do
      reveal = room.reveal |> Map.merge(%{closeness: 83, band: :almost}) |> Map.put(:gap, 7)
      room = %{room | reveal: reveal}

      for mode <- [:phone, :stage, :quiet] do
        html = render_component(&reveal/1, room: room, mode: mode)

        assert html =~ ~s(data-role="ladder-rail")
        assert html =~ ~s(data-role="meld-line")
        assert html =~ "seven short"
      end
    end

    test "a Seat's Call is a pin in its own colour", %{miss_room: room} do
      calls = [%{seat_id: "s1", name: "Mara", band: :close, right?: false, bands_off: 1}]

      room =
        room
        |> Map.put(:reveal, Map.put(room.reveal, :calls, calls))
        |> Map.put(:seats, [%{id: "s1", name: "Mara", colour: "#e11d48"}])

      html = render_component(&reveal/1, room: room)

      assert html =~ ~s(data-role="call-pin")
      assert html =~ ~s(data-seat="s1")
      assert html =~ "--seat-color: #e11d48"
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

    test "names every carried word with commas and a final and" do
      room = %{
        phase: :reveal,
        next_bookends: ~w(cairn beacon wharf signal torch lamp),
        next_bookends_chosen?: true
      }

      html = render_component(&carry_forward/1, room: room)
      assert html =~ "cairn, beacon, wharf, signal, torch and lamp"
    end

    test "says when the Assayer did not choose them" do
      room = %{phase: :reveal, next_bookends: ["cairn", "beacon"], next_bookends_chosen?: false}

      html = render_component(&carry_forward/1, room: room)

      assert html =~ "cairn and beacon"
      assert html =~ "nobody chose"
    end
  end

  describe "foley components" do
    test "foley_switches keeps Voice immediate and moves Quips, Full table, and music into a settings modal" do
      room_with_speaker = %{speaker?: true, quips: true, music: "page"}
      html = render_component(&foley_switches/1, room: room_with_speaker)
      assert html =~ ~s(data-role="quick-sound")
      assert html =~ ~s(data-role="voice-switch")
      assert html =~ ~s(data-role="settings-open")
      assert html =~ ~s(data-role="settings-modal")
      assert html =~ ~s(data-role="voice-bookends-switch")
      assert html =~ ~s(data-role="voice-verdict-switch")
      assert html =~ ~s(data-role="quips-switch")
      assert html =~ ~s(data-role="music-control")
      assert html =~ "Voice"
      assert html =~ "Quips"
      assert html =~ "Off"
      assert html =~ "House"
      assert html =~ "This Page"
      refute html =~ "House loop"
      refute html =~ "Written for this Page"

      # Voice is in the immediate row; Room facts live in the modal
      refute html =~ ~s(data-role="quick-sound") <> ~s() <> ~s(data-role="quips-switch")
      assert html =~ ~s(data-role="settings-modal")

      # Voice master is Speaker-only; Bookends/Verdict prefs are device-owned
      room_without_speaker = %{speaker?: false, quips: false, music: "off"}
      html_without = render_component(&foley_switches/1, room: room_without_speaker)
      refute html_without =~ ~s(data-role="voice-switch")
      assert html_without =~ ~s(data-role="voice-bookends-switch")
      assert html_without =~ ~s(data-role="voice-verdict-switch")
      assert html_without =~ ~s(data-role="settings-open")
      assert html_without =~ ~s(data-role="quips-switch")
      assert html_without =~ "Quips"
      assert html_without =~ ~s(data-role="music-control")
      assert html_without =~ "Off"
      assert html_without =~ "House"
      assert html_without =~ "This Page"
      refute html_without =~ "House loop"
      refute html_without =~ "Written for this Page"
    end

    test "foley_switches renders Full table with its description, and the two-Seat note only at two Seats" do
      two_seats = %{
        speaker?: false,
        quips: true,
        music: "page",
        full_table: true,
        seats: [%{id: "s1"}, %{id: "s2"}]
      }

      html = render_component(&foley_switches/1, room: two_seats)
      assert html =~ ~s(data-role="full-table-switch")
      assert html =~ ~s(data-active="true")

      assert html =~
               "Full table: one Bookend from every player's Give, and every Bridge carries forward"

      assert html =~ ~s(data-role="full-table-note")
      assert html =~ "Matters from three Seats"

      four_seats = %{
        speaker?: false,
        quips: true,
        music: "page",
        full_table: false,
        seats: [%{id: "s1"}, %{id: "s2"}, %{id: "s3"}, %{id: "s4"}]
      }

      html_four = render_component(&foley_switches/1, room: four_seats)
      assert html_four =~ ~s(data-role="full-table-switch")
      assert html_four =~ ~s(data-active="false")
      refute html_four =~ ~s(data-role="full-table-note")
      refute html_four =~ "Matters from three Seats"
    end

    test "reveal quip shows when quips is true and is hidden when quips is false" do
      reveal_data = %{
        closeness: 85,
        band: :meld,
        quip: "Two minds think alike.",
        bridges: [
          %{seat_id: "s1", name: "Mara", bridge: "cairn"},
          %{seat_id: "s2", name: "Jacob", bridge: "cairn"}
        ]
      }

      html_on =
        render_component(&reveal/1,
          room: %{reveal: reveal_data, quips: true, phase: :reveal},
          mode: :stage
        )

      assert html_on =~ ~s(data-role="quip")
      assert html_on =~ "Two minds think alike."

      html_off =
        render_component(&reveal/1,
          room: %{reveal: reveal_data, quips: false, phase: :reveal},
          mode: :stage
        )

      refute html_off =~ ~s(data-role="quip")
      refute html_off =~ "Two minds think alike."
    end

    test "foley_switches renders Next button only when speaker? and next? are both true" do
      room_speaker_with_next = %{speaker?: true, next?: true, voice: true, music: "page"}
      html = render_component(&foley_switches/1, room: room_speaker_with_next)
      assert html =~ ~s(data-role="music-next")
      assert html =~ "Next"

      room_speaker_no_next = %{speaker?: true, next?: false, voice: true, music: "page"}
      html_no_next = render_component(&foley_switches/1, room: room_speaker_no_next)
      refute html_no_next =~ ~s(data-role="music-next")
      refute html_no_next =~ "Next"

      room_non_speaker = %{speaker?: false, next?: true, voice: true, music: "page"}
      html_non_speaker = render_component(&foley_switches/1, room: room_non_speaker)
      refute html_non_speaker =~ ~s(data-role="music-next")
      refute html_non_speaker =~ "Next"
    end

    test "foley_switches renders Never button only when speaker? and never? are both true" do
      room_speaker_with_never = %{speaker?: true, never?: true, voice: true, music: "page"}
      html = render_component(&foley_switches/1, room: room_speaker_with_never)
      assert html =~ ~s(data-role="music-never")
      assert html =~ "Never"

      room_speaker_no_never = %{speaker?: true, never?: false, voice: true, music: "page"}
      html_no_never = render_component(&foley_switches/1, room: room_speaker_no_never)
      refute html_no_never =~ ~s(data-role="music-never")
      refute html_no_never =~ "Never"

      room_non_speaker = %{speaker?: false, never?: true, voice: true, music: "page"}
      html_non_speaker = render_component(&foley_switches/1, room: room_non_speaker)
      refute html_non_speaker =~ ~s(data-role="music-never")
      refute html_non_speaker =~ "Never"
    end

    test "foley_hook renders hook container for colocated Foley hook with configured levels" do
      configured = Thereish.Steward.foley_levels()
      assert is_list(configured) and length(configured) > 0

      html = render_component(&foley_hook/1, speaker: true)
      assert html =~ ~s(id="foley-container")
      assert html =~ ~s(phx-hook="ThereishWeb.RoomComponents.Foley")
      assert html =~ ~s(data-speaker="true")
      assert html =~ ~s(data-level-music="#{configured[:music]}")
      assert html =~ ~s(data-level-stings="#{configured[:stings]}")
      assert html =~ ~s(data-level-voice="#{configured[:voice]}")
      assert html =~ ~s(data-level-duck="#{configured[:duck]}")
      assert html =~ ~s(data-level-duck-stings="#{configured[:duck_stings]}")

      # Redundant non-level prefixed attributes are not rendered
      refute html =~ ~s(data-music=)
      refute html =~ ~s(data-stings=)
      refute html =~ ~s(data-voice=)
      refute html =~ ~s(data-duck=)
      refute html =~ ~s(data-duck-stings=)

      # Custom levels passed explicitly override configured ones
      custom_levels = [music: 0.8, stings: 1.5, voice: 1.0, duck: 0.2, duck_stings: 0.4]
      custom_html = render_component(&foley_hook/1, speaker: true, levels: custom_levels)
      assert custom_html =~ ~s(data-level-music="0.8")
      assert custom_html =~ ~s(data-level-stings="1.5")
      assert custom_html =~ ~s(data-level-voice="1.0")
      assert custom_html =~ ~s(data-level-duck="0.2")
      assert custom_html =~ ~s(data-level-duck-stings="0.4")
    end

    test "foley hook script ducks stings bus during voice, restores on end, and starts arriving cue ducked" do
      hook_source = File.read!("lib/thereish_web/components/room_components.ex")

      assert hook_source =~ "duckStings"
      assert hook_source =~ "restoreStings"
      assert hook_source =~ "isStingsDucked"
      assert hook_source =~ "this.duckStings(duration)"
      assert hook_source =~ "this.restoreStings()"

      # Extract the Foley hook JS from room_components.ex and execute in Node with mock Web Audio
      [_, js_body] =
        Regex.run(
          ~r/<script :type=\{Phoenix\.LiveView\.ColocatedHook\} name="\.Foley">\s*(.*?)\s*<\/script>/s,
          hook_source
        )

      test_script = """
      const assert = require('assert');

      // Mock DOM & Web Audio
      class MockGainNode {
        constructor(ctx) {
          this.ctx = ctx;
          this.gain = {
            value: 1.0,
            setValueAtTime(v, t) { this.value = v; },
            setTargetAtTime(target, startTime, timeConstant) {
              if (startTime <= ctx.currentTime) {
                this.value = target;
              }
            },
            cancelScheduledValues(t) {},
            linearRampToValueAtTime(v, t) { this.value = v; }
          };
        }
        connect(target) {}
      }

      class MockAudioContext {
        constructor() {
          this.currentTime = 10.0;
          this.state = 'running';
          this.destination = {};
        }
        createGain() { return new MockGainNode(this); }
        createBufferSource() {
          return {
            buffer: null,
            connect(b) {},
            start(t) {},
            stop() {}
          };
        }
        decodeAudioData(buf) { return Promise.resolve({ duration: 4.0 }); }
        resume() { return Promise.resolve(); }
      }

      const storage = { "foley:voice": "on", "foley:voice-verdict": "on" };
      global.localStorage = {
        getItem: (k) => (Object.prototype.hasOwnProperty.call(storage, k) ? storage[k] : null),
        setItem: (k, v) => { storage[k] = String(v); }
      };

      global.window = {
        AudioContext: MockAudioContext,
        matchMedia: () => ({ matches: false }),
        localStorage: global.localStorage
      };
      global.fetch = () => Promise.resolve({
        ok: true,
        arrayBuffer: () => Promise.resolve(new ArrayBuffer(8))
      });
      const listeners = {};
      global.document = {
        getElementById: () => null,
        querySelector: (sel) => (sel === "[data-role=quip]" ? {} : null),
        addEventListener: (name, fn) => {
          listeners[name] = listeners[name] || [];
          listeners[name].push(fn);
        },
        removeEventListener: (name, fn) => {
          listeners[name] = (listeners[name] || []).filter((f) => f !== fn);
        },
        dispatchEvent: (event) => {
          (listeners[event.type] || []).forEach((fn) => fn(event));
          return true;
        },
        body: {}
      };

      // Wrap exported hook
      const moduleCode = #{Jason.encode!(js_body)};
      const hookExport = eval('(function() { const exports = {}; ' + moduleCode.replace('export default', 'return') + ' })()');

      (async () => {
        // 1. Voice event during a playing cue ducks stings bus and restores on end
        {
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          // Stings bus starts at normal stings level 1.2
          assert.strictEqual(hook.stingsBus.gain.value, 1.2);

          // Victory cue starts playing via foley:ending event
          await events["foley:ending"]({kind: "meld"});
          assert.strictEqual(hook.stingsBus.gain.value, 1.2);

          // While cue is playing, voice event arrives and quip is ready
          await events["foley:voice"]({attempt: 1, url: "/voice/1"});
          assert.strictEqual(hook.isStingsDucked(), true);
          assert.strictEqual(hook.stingsBus.gain.value, 0.35);

          // When voice ends, stings bus restores to 1.2
          hook.voiceSource.onended();
          assert.strictEqual(hook.isStingsDucked(), false);
          assert.strictEqual(hook.stingsBus.gain.value, 1.2);
        }

        // 2. Cue arriving during a playing voice starts ducked
        {
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          // Voice starts playing first via foley:voice event
          await events["foley:voice"]({attempt: 1, url: "/voice/1"});
          assert.strictEqual(hook.isStingsDucked(), true);
          assert.strictEqual(hook.stingsBus.gain.value, 0.35);

          // Cue arrives during playing voice via foley:ending event
          await events["foley:ending"]({kind: "deep_meld"});
          // Stings bus remains ducked under the active voice
          assert.strictEqual(hook.stingsBus.gain.value, 0.35);

          // When voice ends, stings bus restores to 1.2
          hook.voiceSource.onended();
          assert.strictEqual(hook.isStingsDucked(), false);
          assert.strictEqual(hook.stingsBus.gain.value, 1.2);
        }

        // 3. When localStorage has voice off, voice does not play / does not duck stings
        {
          storage["foley:voice"] = "off";
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:voice"]({attempt: 1, url: "/voice/1"});
          assert.strictEqual(hook.isStingsDucked(), false);
        }

        // 4. When voice is on, foley:prologue plays reading and ducks music
        {
          storage["foley:voice"] = "on";
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:prologue"]({path: "/audio/prologue-1.mp3"});
          assert.strictEqual(hook.isDucked(), true);
          assert.notStrictEqual(hook.voiceSource, null);

          // When voice ends, music is restored
          hook.voiceSource.onended();
          assert.strictEqual(hook.isDucked(), false);
          assert.strictEqual(hook.voiceSource, null);
        }

        // 5. When voice is off, foley:prologue stays silent and does not duck music
        {
          storage["foley:voice"] = "off";
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:prologue"]({path: "/audio/prologue-1.mp3"});
          assert.strictEqual(hook.isDucked(), false);
          assert.strictEqual(hook.voiceSource, null);
        }

        // 6. Bookends play immediately, without waiting for the reveal
        {
          storage["foley:voice"] = "on";
          delete storage["foley:voice-verdict"];
          delete storage["foley:voice-bookends"];
          const previousQuery = global.document.querySelector;
          global.document.querySelector = () => null;
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:voice"]({attempt: 1, url: "/voice/1/bookends", kind: "bookends"});
          assert.notStrictEqual(hook.voiceSource, null);
          assert.strictEqual(hook.isDucked(), true);
          global.document.querySelector = previousQuery;
        }

        // 7. Verdict speech stays off until that choice is enabled
        {
          storage["foley:voice"] = "on";
          delete storage["foley:voice-verdict"];
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:voice"]({attempt: 1, url: "/voice/1", kind: "verdict"});
          assert.strictEqual(hook.voiceSource, null);
          assert.strictEqual(hook.isStingsDucked(), false);
        }

        // 8. Disabling Voice stops speech that is already playing
        {
          storage["foley:voice"] = "on";
          delete storage["foley:voice-bookends"];
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:voice"]({attempt: 1, url: "/voice/1/bookends", kind: "bookends"});
          assert.notStrictEqual(hook.voiceSource, null);

          global.document.dispatchEvent({ type: "thereish:voice-pref", detail: { enabled: false, kind: "master" } });
          assert.strictEqual(hook.voiceSource, null);
        }

        // 9. foley:stop_voice cancels speech; a later Attempt's Bookends replace the earlier one
        {
          storage["foley:voice"] = "on";
          delete storage["foley:voice-bookends"];
          const el = {
            dataset: {
              speaker: 'true',
              mode: 'speaker',
              levelMusic: '0.5',
              levelStings: '1.2',
              levelVoice: '1.2',
              levelDuck: '0.15',
              levelDuckStings: '0.35',
              meldCueDelayMs: '0'
            }
          };

          const hook = Object.create(hookExport);
          hook.el = el;
          const events = {};
          hook.handleEvent = (name, fn) => { events[name] = fn; };
          hook.mounted();
          hook.initAudio();

          await events["foley:voice"]({attempt: 1, url: "/voice/1/bookends", kind: "bookends"});
          assert.notStrictEqual(hook.voiceSource, null);

          events["foley:stop_voice"]({attempt: 2});
          assert.strictEqual(hook.voiceSource, null);
          assert.strictEqual(hook.currentVoiceAttempt, null);

          await events["foley:voice"]({attempt: 2, url: "/voice/2/bookends", kind: "bookends"});
          assert.notStrictEqual(hook.voiceSource, null);
          assert.strictEqual(hook.currentVoiceAttempt, 2);

          await events["foley:voice"]({attempt: 1, url: "/voice/1/bookends", kind: "bookends"});
          assert.strictEqual(hook.currentVoiceAttempt, 2);
        }

        console.log('HOOK_TESTS_PASSED');
      })().catch(err => {
        console.error(err);
        process.exit(1);
      });
      """

      {output, exit_code} = System.cmd("node", ["-e", test_script])
      assert exit_code == 0
      assert output =~ "HOOK_TESTS_PASSED"
    end

    test "foley_hook renders meld cue delay and hook script handles meld, deep_meld, and unmelded" do
      default_delay = Thereish.Steward.foley_meld_cue_delay_ms()
      assert is_integer(default_delay) and default_delay > 0

      html = render_component(&foley_hook/1, speaker: true)
      assert html =~ ~s(data-meld-cue-delay-ms="#{default_delay}")

      # Custom delay overrides configured one
      custom_html = render_component(&foley_hook/1, speaker: true, meld_cue_delay_ms: 2500)
      assert custom_html =~ ~s(data-meld-cue-delay-ms="2500")

      # Script in room_components handles meld and deep_meld with victory cues and fadeMusicOut
      hook_source = File.read!("lib/thereish_web/components/room_components.ex")
      assert hook_source =~ "victory-meld.mp3"
      assert hook_source =~ "victory-deep-meld.mp3"
      assert hook_source =~ "ending-unmelded.mp3"
      assert hook_source =~ "fadeMusicOut(2.0)"
      refute hook_source =~ ~s("/audio/ending-meld.mp3")
    end

    test "local_sound_switch renders button with colocated LocalSoundToggle hook and default on state" do
      html = render_component(&local_sound_switch/1, %{})
      assert html =~ ~s(id="local-sound-toggle")
      assert html =~ ~s(phx-hook="ThereishWeb.RoomComponents.LocalSoundToggle")
      assert html =~ ~s(data-role="local-sound-toggle")
      assert html =~ ~s(data-sound="on")
      assert html =~ ~s(data-state="on")
      assert html =~ ~s(data-state="off")
    end

    test "local_sound_switch renders title and aria-label reflecting whether stage is present" do
      html_without_stage = render_component(&local_sound_switch/1, %{stage_present?: false})
      assert html_without_stage =~ ~s(title="Toggle commit sound on this device")
      assert html_without_stage =~ ~s(aria-label="Toggle commit sound on this device")

      html_with_stage = render_component(&local_sound_switch/1, %{stage_present?: true})
      assert html_with_stage =~ ~s(title="Commit sound plays from the Stage while connected")

      assert html_with_stage =~
               ~s[aria-label="Toggle commit sound on this device (commit sound plays from the Stage while connected)"]
    end
  end

  describe "bookends component" do
    @six ~w(lantern harbour summit ember grove spire)

    test "renders a wrapping row of word chips under the Bookends caption at any count" do
      room = %{bookends: @six}

      for mode <- [:phone, :stage] do
        html = render_component(&bookends/1, room: room, mode: mode)
        assert html =~ "Bookends"
        assert html =~ ~s(data-role="bookends-caption")
        assert html =~ "flex-wrap"
        assert html =~ ~s(data-role="bookend-chip")

        for word <- @six do
          assert html =~ word
        end

        refute html =~ ~s(data-role="bookend-mask")
      end
    end

    test "an optional Mask sits beside a carried word" do
      room = %{
        bookends: ["cairn", "beacon"],
        bookend_chips: [
          %{word: "cairn", mask: %Mask{url: "/media/masks/m.png", meta: %{}}, seat_id: "s1"},
          %{word: "beacon", mask: %Mask{url: "/media/masks/j.png", meta: %{}}, seat_id: "s2"}
        ]
      }

      html = render_component(&bookends/1, room: room, mode: :phone)
      assert html =~ ~s(data-role="bookend-mask")
      assert html =~ "/media/masks/m.png"
      assert html =~ "/media/masks/j.png"
      assert html =~ "cairn"
      assert html =~ "beacon"
    end

    test "first-Attempt Bookends never show a Mask" do
      room = %{
        bookends: ["lantern", "harbour"],
        bookend_chips: [
          %{word: "lantern", mask: nil, give: "lighthouse"},
          %{word: "harbour", mask: nil, give: "candle"}
        ]
      }

      html = render_component(&bookends/1, room: room, mode: :phone)
      refute html =~ ~s(data-role="bookend-mask")
      assert html =~ "lantern"
      assert html =~ "harbour"
    end
  end

  describe "join_and" do
    test "two words stay 'cairn and beacon'; six take commas and a final and" do
      assert join_and(["cairn", "beacon"]) == "cairn and beacon"

      assert join_and(~w(cairn beacon wharf signal torch lamp)) ==
               "cairn, beacon, wharf, signal, torch and lamp"
    end
  end

  describe "caption component" do
    test "renders slot content with shared caption styling" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.caption data-role="test-caption" class="custom-class">
          Test Caption Content
        </.caption>
        """)

      assert html =~ "Test Caption Content"
      assert html =~ "text-center text-sm uppercase tracking-widest opacity-60"
      assert html =~ "custom-class"
      assert html =~ ~s(data-role="test-caption")
    end
  end

  describe "now_playing component" do
    test "renders 'Music is off' when music is off" do
      room = %{music: "off", phase: :bridging, loop: nil, playing: nil}
      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Music is off"
      refute html =~ "The Porch"
    end

    test "renders 'Music is off' during the reveal" do
      room = %{music: "off", phase: :reveal, first_revealed?: true, loop: nil, playing: nil}
      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Music is off"
    end

    test "renders loop name and 'the Repertoire' under house" do
      room = %{
        music: "house",
        loop: %{name: "Sunlit Drift", path: "/audio/house-loop-2.mp3"},
        playing: %{title: "Sunlit Drift", path: "/audio/house-loop-2.mp3", kind: "repertoire"}
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Sunlit Drift"
      assert html =~ "the Repertoire"
      refute html =~ "Music is off"
    end

    test "renders loop name and 'the Repertoire' under page before track lands" do
      room = %{
        music: "page",
        loop: %{name: "Morning Breeze", path: "/audio/house-loop-3.mp3"},
        track: nil,
        playing: %{title: "Morning Breeze", path: "/audio/house-loop-3.mp3", kind: "repertoire"}
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Morning Breeze"
      assert html =~ "the Repertoire"
    end

    test "renders Repertoire draw title and 'the Repertoire' when playing is on snapshot" do
      room = %{
        music: "page",
        playing: %{title: "Cabin Warmth", path: "/media/tracks/cabin.mp3", kind: "repertoire"},
        track: nil
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Cabin Warmth"
      assert html =~ "the Repertoire"
    end

    test "renders last Page's Track and keeps title when playing kind is holdover" do
      room = %{
        music: "page",
        playing: %{
          title: "Summer Camp · Viking Beaches",
          path: "/media/tracks/p1.mp3",
          kind: "holdover"
        }
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Summer Camp · Viking Beaches"
      assert html =~ "last Page&#39;s Track"
      refute html =~ "the Repertoire"
      refute html =~ "written for this Page"
    end

    test "renders 'written for this Page' without title before reveal when playing kind is track" do
      room = %{
        music: "page",
        phase: :bridging,
        first_revealed?: false,
        playing: %{
          title: "Summer Camp · Viking Beaches",
          path: "/media/tracks/p1.mp3",
          kind: "track"
        }
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Now playing: written for this Page"
      refute html =~ "Summer Camp · Viking Beaches"
    end

    test "renders title and 'written for this Page' during reveal when playing kind is track" do
      room = %{
        music: "page",
        phase: :reveal,
        first_revealed?: true,
        playing: %{
          title: "Summer Camp · Viking Beaches",
          path: "/media/tracks/p1.mp3",
          kind: "track"
        }
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Now playing: Summer Camp · Viking Beaches (written for this Page)"
    end

    test "renders title and 'written for this Page' after first reveal on subsequent attempt" do
      room = %{
        music: "page",
        phase: :bridging,
        first_revealed?: true,
        playing: %{
          title: "Summer Camp · Viking Beaches",
          path: "/media/tracks/p1.mp3",
          kind: "track"
        }
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Now playing: Summer Camp · Viking Beaches (written for this Page)"
    end

    test "renders title and 'written for this Page' on closed page" do
      room = %{
        music: "page",
        phase: :closed,
        first_revealed?: true,
        playing: %{
          title: "Summer Camp · Viking Beaches",
          path: "/media/tracks/p1.mp3",
          kind: "track"
        }
      }

      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Now playing: Summer Camp · Viking Beaches (written for this Page)"
    end

    test "renders nothing when room has no loop and music is not off" do
      room = %{music: "page", loop: nil, track: nil, playing: nil}
      html = render_component(&now_playing/1, room: room)

      refute html =~ ~s(data-role="now-playing")
    end

    test "renders nothing when room has no loop and music is off in lobby" do
      room = %{music: "off", loop: nil, track: nil, playing: nil, phase: :waiting}
      html = render_component(&now_playing/1, room: room)

      refute html =~ ~s(data-role="now-playing")
    end
  end

  describe "closed page reveal gives" do
    test "renders every Seat's Give with Seat name on closed page (standard mode)" do
      room = %{
        phase: :closed,
        closed: %{because: :meld, attempt: 1},
        reveal: %{
          mode: :standard,
          bridges: [%{seat_id: "s1", name: "Mara", bridge: "cairn"}],
          closeness: 95,
          band: :deep_meld,
          quip: "one mind",
          gives: [
            %{
              seat_id: "s1",
              name: "Mara",
              text: "lighthouse",
              mask: %Mask{url: "/media/masks/mask-mara.png", meta: %{}}
            },
            %{
              seat_id: "s2",
              name: "Jacob",
              text: "candle",
              mask: %Mask{url: "/media/masks/mask-jacob.png", meta: %{}}
            }
          ]
        }
      }

      html = render_component(&reveal/1, room: room, mode: :stage, seat: nil)

      assert html =~ ~s(data-role="gives")
      assert html =~ ~s(data-role="give")
      assert html =~ "Mara"
      assert html =~ "lighthouse"
      assert html =~ "Jacob"
      assert html =~ "candle"
      assert html =~ ~s(data-role="give-mask")
      assert html =~ "/media/masks/mask-mara.png"
      assert html =~ "/media/masks/mask-jacob.png"
      refute html =~ "Settings:"
      assert html =~ "Gives"
      assert html =~ "size-16" or html =~ "size-20" or html =~ "text-lg"
    end

    test "does not render gives before page is closed" do
      room = %{
        phase: :reveal,
        closed: nil,
        reveal: %{
          mode: :standard,
          bridges: [%{seat_id: "s1", name: "Mara", bridge: "cairn"}],
          closeness: 85,
          band: :warm,
          quip: "close enough",
          gives: [
            %{seat_id: "s1", name: "Mara", text: "lighthouse"},
            %{seat_id: "s2", name: "Jacob", text: "candle"}
          ]
        }
      }

      html = render_component(&reveal/1, room: room, mode: :stage, seat: nil)

      refute html =~ ~s(data-role="gives")
    end
  end

  describe "the noise at the punchline, and the labour moved off it" do
    defp revealed_room(overrides \\ %{}) do
      Map.merge(
        %{
          phase: :reveal,
          may: %{react: true, tap_fairness: true},
          reactions: [],
          closed: nil,
          played: [],
          reveal: %{
            closeness: 83,
            band: :almost,
            melded?: false,
            gap: 7,
            bridges: [
              %{seat_id: "s1", name: "Mara", bridge: "cairn"},
              %{seat_id: "s2", name: "Jacob", bridge: "beacon"}
            ],
            graded?: true,
            overruled?: false,
            quip: "Nearly the same hill.",
            reasoning: "Stones, both.",
            furthest: nil
          }
        },
        overrides
      )
    end

    defp closed_room(overrides \\ %{}) do
      revealed_room(
        Map.merge(
          %{
            phase: :closed,
            closed: %{because: :meld, attempt: 2},
            may: %{react: true, tap_fairness: true, tap_bookends: true}
          },
          overrides
        )
      )
    end

    test "the four words are offered on the phone and on a quiet phone" do
      for mode <- [:phone, :quiet] do
        html = render_component(&reveal/1, room: revealed_room(), mode: mode)

        assert html =~ ~s(data-role="reactions")

        for reaction <- Thereish.Game.reactions() do
          assert html =~ ~s(data-reaction="#{reaction}")
        end

        assert html =~ "no way"
      end
    end

    test "the Stage performs the reveal and offers no buttons" do
      html = render_component(&reveal/1, room: revealed_room(), mode: :stage)

      refute html =~ ~s(data-role="reactions")
    end

    test "a Seat that may not react is offered nothing" do
      room = revealed_room(%{may: %{react: false}})

      refute render_component(&reveal/1, room: room, mode: :phone) =~ ~s(data-role="reactions")
    end

    test "your own word is the chosen one, and nobody's is counted" do
      room =
        revealed_room(%{
          reactions: [
            %{seat_id: "s1", name: "Mara", reaction: :ooh},
            %{seat_id: "s2", name: "Jacob", reaction: :ooh}
          ]
        })

      html =
        render_component(&reveal/1,
          room: room,
          seat: %{id: "s1", name: "Mara"},
          mode: :phone
        )

      assert html =~ ~s(data-reaction="ooh" data-chosen="true")
      assert html =~ ~s(data-reaction="yes" data-chosen="false")

      # Two Seats shouted the same word and the screen says so nowhere: there
      # is no score in this game and a reaction tally would be one.
      refute html =~ "×2"
      refute html =~ ~s(data-count)
      refute html =~ "reaction-count"
    end

    test "the fairness tap has left the reveal" do
      for mode <- [:phone, :quiet, :stage] do
        html = render_component(&reveal/1, room: revealed_room(), mode: mode)

        refute html =~ ~s(data-role="fairness-controls")
        refute html =~ "Was this grade fair?"
      end
    end

    test "the fairness tap and the Bookends taps are on the closing card, behind Notes" do
      html = render_component(&ending/1, room: closed_room(), seat: %{id: "s1", name: "Mara"})

      assert html =~ ~s(data-role="notes")
      assert html =~ "Notes"
      assert html =~ ~s(data-role="fairness-controls")
      assert html =~ ~s(data-role="bookends-controls")

      # The ending line and the arc still own the card.
      {ending_idx, _} = :binary.match(html, ~s(data-role="ending-line"))
      {notes_idx, _} = :binary.match(html, ~s(data-role="notes"))
      assert ending_idx < notes_idx
    end

    test "the Stage's closing card carries no taps" do
      html = render_component(&ending/1, room: closed_room(), mode: :stage)

      refute html =~ ~s(data-role="notes")
      refute html =~ ~s(data-role="fairness-controls")
    end

    test "a closing card nobody may tap has no Notes at all" do
      html = render_component(&ending/1, room: closed_room(%{may: %{}}))

      refute html =~ ~s(data-role="notes")
    end
  end

  describe "the Juice hook" do
    test "the hand is wired on the phone and the floats are the Stage's" do
      room = %{attempt: %{number: 2, of: 5}, reactions: []}

      phone = render_component(&juice_hook/1, room: room)
      stage = render_component(&juice_hook/1, room: room, floats: true)

      assert phone =~ "Juice"
      assert phone =~ ~s(data-floats="false")
      assert stage =~ ~s(data-floats="true")
      assert phone =~ ~s(data-attempt="2")
    end

    test "the Reactions reach the hook as who shouted what, never how many" do
      room = %{
        attempt: %{number: 1, of: 5},
        reactions: [
          %{seat_id: "s1", name: "Mara", reaction: :ooh},
          %{seat_id: "s2", name: "Jacob", reaction: :no_way}
        ]
      }

      html = render_component(&juice_hook/1, room: room, floats: true)

      assert html =~ ~s(data-reactions="s1:ooh s2:no_way")
      refute html =~ ~s(data-reactions="2")
    end

    test "a Room that has not loaded yet still renders" do
      assert render_component(&juice_hook/1, room: nil) =~ ~s(id="juice-container")
    end
  end

  describe "the Buzz switch" do
    test "is a device preference in the settings card, with no Room fact behind it" do
      html = render_component(&foley_switches/1, room: %{speaker?: true, music: "page"})

      assert html =~ ~s(data-role="buzz-switch")
      assert html =~ ~s(data-pref="juice:haptics")
      assert html =~ ~s(data-default="on")
      assert html =~ "Buzz"
      refute html =~ "toggle_buzz"
    end
  end

  describe "the Split reading on screen" do
    @split %{
      forward: 31,
      reverse: 78,
      reasoning: "They both name a light.",
      reasoning_reverse: "They share nothing but the bookends.",
      generous: 78
    }

    defp split_room(overrides \\ %{}) do
      revealed_room(
        Map.merge(%{reveal: Map.put(revealed_room().reveal, :split, @split)}, overrides)
      )
    end

    test "both readings are drawn on the Rail and written under it, on every screen" do
      for mode <- [:phone, :stage, :quiet] do
        html = render_component(&reveal/1, room: split_room(), mode: mode)

        assert html =~ ~s(data-role="split-reading"), "#{mode}"
        assert html =~ "graded this twice"
        assert html =~ @split.reasoning
        assert html =~ @split.reasoning_reverse

        # The same two numbers, on the same scale as the grade: the argument is
        # a distance the table can see rather than a claim it has to take.
        assert html =~ ~s(data-role="rail-mark")
        assert html =~ "31"
        assert html =~ "78"
      end
    end

    test "a Room that turned Split readings off is shown neither pins nor sentences" do
      html = render_component(&reveal/1, room: split_room(%{split_readings: false}), mode: :phone)

      refute html =~ ~s(data-role="split-reading")
      refute html =~ ~s(data-role="rail-mark")
      refute html =~ @split.reasoning
    end

    test "a reveal the Assayer agreed with itself about shows nothing of either" do
      html = render_component(&reveal/1, room: revealed_room(), mode: :phone)

      refute html =~ ~s(data-role="split-reading")
      refute html =~ ~s(data-role="rail-mark")
    end

    test "the Assayer's reasoning stays off every other reveal" do
      html = render_component(&reveal/1, room: revealed_room(), mode: :stage)

      refute html =~ "Stones, both."
    end

    test "the Room's off switch is in the settings card beside Full table" do
      html = render_component(&foley_switches/1, room: %{speaker?: true, music: "page"})

      assert html =~ ~s(data-role="split-readings-switch")
      assert html =~ ~s(phx-click="toggle_split_readings")
      # On unless a flat night turns it off, like the other Room facts.
      assert html =~ ~s(data-role="split-readings-switch" data-active="true")
    end

    test "a declined overrule says who declined for the rest of the Attempt" do
      room = %{
        overrule: nil,
        overrule_declined: %{seat_id: "s2", name: "Jacob"},
        reveal: %{overruled?: false},
        may: %{}
      }

      html = render_component(&overrule_banner/1, room: room)

      assert html =~ ~s(data-role="overrule-declined")
      assert html =~ "Jacob"
      assert html =~ "The Assayer's grade stands"
    end

    test "a proposal still on the table outranks a decline said earlier" do
      room = %{
        overrule: %{
          pending?: true,
          proposer_name: "Mara",
          you_proposed?: false,
          you_agreed?: false
        },
        overrule_declined: %{seat_id: "s2", name: "Jacob"},
        reveal: %{overruled?: false},
        may: %{}
      }

      html = render_component(&overrule_banner/1, room: room)

      assert html =~ ~s(data-role="overrule-banner")
      refute html =~ ~s(data-role="overrule-declined")
    end
  end
end
