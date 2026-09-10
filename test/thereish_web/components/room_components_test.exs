defmodule ThereishWeb.RoomComponentsTest do
  use ThereishWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import ThereishWeb.RoomComponents

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

  describe "roster couples" do
    test "roster highlights couples with partner names" do
      room = %{
        seats: [
          %{
            id: "s1",
            name: "Mara",
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
            partner_name: "Mara"
          }
        ],
        open_seats: 0,
        seat_limit: 2,
        phase: :waiting
      }

      html = render_component(&roster/1, room: room)

      assert html =~ ~s(data-role="partner")
      assert html =~ "(with Jacob)"
      assert html =~ "(with Mara)"
      assert html =~ ~s(data-couple="true")
    end

    test "roster in :stage mode renders as a compact horizontal strip" do
      room = %{
        seats: [
          %{
            id: "s1",
            name: "Mara",
            you?: false,
            committed?: true
          },
          %{
            id: "s2",
            name: "Jacob",
            you?: false,
            committed?: false
          }
        ],
        open_seats: 0,
        seat_limit: 2,
        phase: :bridging
      }

      html = render_component(&roster/1, room: room, mode: :stage)

      assert html =~ ~s(data-role="roster")
      assert html =~ ~s(data-mode="stage")
      assert html =~ ~s(data-seat="s1")
      assert html =~ ~s(data-committed="true")
      assert html =~ "Mara"
      assert html =~ ~s(data-seat="s2")
      assert html =~ "Jacob"
      refute html =~ ~s(data-role="open-seats")
    end

    test "renders 'Waiting for 1 more' at one Seat, and no fill line at two or more" do
      one_seat_room = %{
        seats: [%{id: "s1", name: "Mara", committed?: false, you?: false}],
        open_seats: 5,
        seat_limit: 6
      }

      html1 = render_component(&roster/1, room: one_seat_room)
      assert html1 =~ ~s(data-role="open-seats")
      assert html1 =~ "Waiting for 1 more"

      two_seat_room = %{
        seats: [
          %{id: "s1", name: "Mara", committed?: false, you?: false},
          %{id: "s2", name: "Jacob", committed?: false, you?: false}
        ],
        open_seats: 4,
        seat_limit: 6
      }

      html2 = render_component(&roster/1, room: two_seat_room)
      refute html2 =~ ~s(data-role="open-seats")
      refute html2 =~ "Waiting for"

      three_seat_room = %{
        seats: [
          %{id: "s1", name: "Mara", committed?: false, you?: false},
          %{id: "s2", name: "Jacob", committed?: false, you?: false},
          %{id: "s3", name: "Ada", committed?: false, you?: false}
        ],
        open_seats: 3,
        seat_limit: 6
      }

      html3 = render_component(&roster/1, room: three_seat_room)
      refute html3 =~ ~s(data-role="open-seats")

      empty_room = %{
        seats: [],
        open_seats: 6,
        seat_limit: 6
      }

      html0 = render_component(&roster/1, room: empty_room)
      refute html0 =~ ~s(data-role="open-seats")
    end
  end

  describe "couples on the reveal and stage meld map" do
    setup do
      pairs = [
        %{
          seat_ids: ["s1", "s2"],
          names: ["Mara", "Jacob"],
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
          names: ["Mara", "Ida"],
          bridges: ["cairn", "beacon"],
          closeness: 85,
          band: :meld,
          melded?: true,
          couple?: false,
          cross_couple?: true,
          cross_couple_meld?: true,
          surprise: "Mara and Ida think alike"
        }
      ]

      room = %{
        phase: :reveal,
        reveal: %{
          closeness: 65,
          band: :close,
          melded?: false,
          bridges: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
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
      mara_seat = %{id: "s1", name: "Mara"}
      html = render_component(&reveal/1, room: room, seat: mara_seat, mode: :phone)

      # Displays own couple pair closeness
      assert html =~ ~s(data-role="own-couple-pair")
      assert html =~ ~s(data-role="couple-closeness")
      assert html =~ "Your couple: Mara &amp; Jacob"
      assert html =~ "80"

      # Displays surprise cross-couple meld alert
      assert html =~ ~s(data-role="cross-couple-meld")
      assert html =~ "Mara and Ida think alike"
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
      assert html =~ "Mara and Ida think alike"
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

  describe "foley components" do
    test "foley_switches renders voice switch only on speaker, and quips switch on any view" do
      room_with_speaker = %{speaker?: true, quips: true, music: "page"}
      html = render_component(&foley_switches/1, room: room_with_speaker)
      assert html =~ ~s(data-role="voice-switch")
      assert html =~ ~s(data-role="quips-switch")
      assert html =~ ~s(data-role="music-control")
      assert html =~ "Voice"
      assert html =~ "Quips"
      assert html =~ "Off"
      assert html =~ "House"
      assert html =~ "This Page"
      refute html =~ "House loop"
      refute html =~ "Written for this Page"

      # Voice switch does NOT render without speaker, but Quips switch does
      room_without_speaker = %{speaker?: false, quips: false, music: "off"}
      html_without = render_component(&foley_switches/1, room: room_without_speaker)
      refute html_without =~ ~s(data-role="voice-switch")
      refute html_without =~ "Voice"
      assert html_without =~ ~s(data-role="quips-switch")
      assert html_without =~ "Quips"
      assert html_without =~ ~s(data-role="music-control")
      assert html_without =~ "Off"
      assert html_without =~ "House"
      assert html_without =~ "This Page"
      refute html_without =~ "House loop"
      refute html_without =~ "Written for this Page"
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
        render_component(&reveal/1, room: %{reveal: reveal_data, quips: true}, mode: :stage)

      assert html_on =~ ~s(data-role="quip")
      assert html_on =~ "Two minds think alike."

      html_off =
        render_component(&reveal/1, room: %{reveal: reveal_data, quips: false}, mode: :stage)

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

      const storage = { "foley:voice": "on" };
      global.localStorage = {
        getItem: (k) => storage[k] || null,
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
      global.document = {
        getElementById: () => null,
        querySelector: (sel) => (sel === "[data-role=quip]" ? {} : null),
        addEventListener: () => {},
        removeEventListener: () => {},
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

  describe "Sides: couple versus couple components" do
    test "roster renders sides grouping when in Sides mode" do
      room = %{
        seats: [
          %{id: "s1", name: "Mara", you?: true, committed?: false},
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
            name: "Mara & Jacob",
            you?: true,
            seat_ids: ["s1", "s2"],
            seats: [
              %{id: "s1", name: "Mara", you?: true, committed?: false},
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
      assert html =~ "Mara &amp; Jacob"
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
              name: "Mara & Jacob",
              seat_ids: ["s1", "s2"],
              closer?: false,
              melded?: false,
              graded?: true,
              closeness: 82,
              band: :almost,
              quip: "Almost touching.",
              bridges: [
                %{seat_id: "s1", name: "Mara", bridge: "cairn"},
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
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s2", name: "Jacob", bridge: "cairo"},
            %{seat_id: "s3", name: "Ada", bridge: "beacon"},
            %{seat_id: "s4", name: "Sam", bridge: "lighthouse"}
          ],
          furthest: [
            %{seat_id: "s1", name: "Mara", bridge: "cairn"},
            %{seat_id: "s4", name: "Sam", bridge: "lighthouse"}
          ]
        }
      }

      seat = %{id: "s1", name: "Mara"}
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
          proposer_name: "Mara",
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

      opponent_html =
        render_component(&overrule_banner/1, room: opposing_room, seat: opponent_seat)

      refute opponent_html =~ ~s(data-role="overrule-vote")

      assert opponent_html =~
               "proposed an overrule for their Side. Waiting for their partner to agree."
    end
  end

  describe "bookends component" do
    test "renders a 'Bookends' caption on the Stage, but no label on phones" do
      room = %{
        bookends: ["lantern", "harbour"]
      }

      stage_html = render_component(&bookends/1, room: room, mode: :stage)
      assert stage_html =~ "Bookends"
      assert stage_html =~ ~s(data-role="bookends-caption")
      assert stage_html =~ "text-center text-sm uppercase tracking-widest opacity-60"
      assert stage_html =~ "lantern"
      assert stage_html =~ "harbour"

      phone_html = render_component(&bookends/1, room: room, mode: :phone)
      refute phone_html =~ "Bookends"
      refute phone_html =~ ~s(data-role="bookends-caption")
      assert phone_html =~ "lantern"
      assert phone_html =~ "harbour"

      # Default mode is :phone
      default_html = render_component(&bookends/1, room: room)
      refute default_html =~ "Bookends"
      refute default_html =~ ~s(data-role="bookends-caption")
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
      room = %{music: "off", loop: %{name: "The Porch", path: "/audio/house-loop.mp3"}}
      html = render_component(&now_playing/1, room: room)

      assert html =~ ~s(data-role="now-playing")
      assert html =~ "Music is off"
      refute html =~ "The Porch"
    end

    test "renders loop name and 'the Repertoire' under house" do
      room = %{music: "house", loop: %{name: "Sunlit Drift", path: "/audio/house-loop-2.mp3"}}
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
        track: nil
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
        played: [],
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
        played: [],
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
        played: [%{attempt: 1}],
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
        played: [%{attempt: 1}],
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

    test "renders nothing when track has landed without title" do
      room = %{
        music: "page",
        loop: %{name: "Morning Breeze", path: "/audio/house-loop-3.mp3"},
        track: %{path: "/audio/track-1.mp3"}
      }

      html = render_component(&now_playing/1, room: room)

      refute html =~ ~s(data-role="now-playing")
      refute html =~ "the Repertoire"
    end

    test "renders nothing when room has no loop and music is not off" do
      room = %{music: "page", loop: nil, track: nil}
      html = render_component(&now_playing/1, room: room)

      refute html =~ ~s(data-role="now-playing")
    end

    test "renders nothing when room has no loop and music is off in lobby" do
      room = %{music: "off", loop: nil, track: nil, phase: :waiting}
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
            %{seat_id: "s1", name: "Mara", text: "lighthouse"},
            %{seat_id: "s2", name: "Jacob", text: "candle"}
          ]
        }
      }

      html = render_component(&reveal/1, room: room, mode: :stage, seat: nil)

      assert html =~ ~s(data-role="gives")
      assert html =~ ~s(data-role="give")
      assert html =~ "Mara:"
      assert html =~ "lighthouse"
      assert html =~ "Jacob:"
      assert html =~ "candle"
    end

    test "renders every Seat's Give with Seat name on closed page (sides mode)" do
      room = %{
        phase: :closed,
        closed: %{because: :meld, attempt: 1},
        reveal: %{
          mode: :sides,
          sides: [],
          closeness: 95,
          band: :deep_meld,
          quip: "one mind",
          gives: [
            %{seat_id: "s1", name: "Mara", text: "lighthouse"},
            %{seat_id: "s2", name: "Jacob", text: "candle"}
          ]
        }
      }

      html = render_component(&reveal/1, room: room, mode: :phone, seat: nil)

      assert html =~ ~s(data-role="gives")
      assert html =~ ~s(data-role="give")
      assert html =~ "Mara:"
      assert html =~ "lighthouse"
      assert html =~ "Jacob:"
      assert html =~ "candle"
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
end
