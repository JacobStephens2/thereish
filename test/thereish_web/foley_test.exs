defmodule ThereishWeb.FoleyTest do
  use ExUnit.Case, async: true

  alias ThereishWeb.Foley
  alias Phoenix.LiveView.Socket

  defp test_socket(view \\ ThereishWeb.RoomLive) do
    %Socket{
      endpoint: ThereishWeb.Endpoint,
      view: view,
      private: %{live_temp: %{}}
    }
  end

  defp pushed_events(socket) do
    socket
    |> Phoenix.LiveView.Utils.get_push_events()
    |> Enum.map(fn [event, payload | _] -> {event, payload} end)
  end

  describe "push_foley_events/4 ending events" do
    test "pushes :meld when closed because of meld with meld band" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld, attempt: 1},
        reveal: %{band: :meld}
      }

      socket = test_socket()
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert {"foley:ending", %{kind: :meld}} in pushed_events(result)
    end

    test "pushes :deep_meld when closed because of meld with deep_meld band" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld, attempt: 1},
        reveal: %{band: :deep_meld}
      }

      socket = test_socket()
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert {"foley:ending", %{kind: :deep_meld}} in pushed_events(result)
    end

    test "pushes :unmelded when closed because of attempts_spent" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :attempts_spent, attempt: 5},
        reveal: %{band: :miss}
      }

      socket = test_socket()
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert {"foley:ending", %{kind: :unmelded}} in pushed_events(result)
    end

    test "pushes :deep_meld in sides mode when one side achieved deep_meld" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld, attempt: 2},
        reveal: %{
          sides: [
            %{id: :a, band: :meld},
            %{id: :b, band: :deep_meld}
          ]
        }
      }

      socket = test_socket()
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert {"foley:ending", %{kind: :deep_meld}} in pushed_events(result)
    end

    test "does not push ending when already closed" do
      old_room = %{phase: :closed, speaker?: true, closed: %{because: :meld}}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld},
        reveal: %{band: :meld}
      }

      socket = test_socket()
      result = Foley.push_foley_events(socket, old_room, new_room)

      refute Enum.any?(pushed_events(result), fn {name, _} -> name == "foley:ending" end)
    end

    test "does not push ending to non-speaker" do
      old_room = %{phase: :reveal, speaker?: false}

      new_room = %{
        phase: :closed,
        speaker?: false,
        closed: %{because: :meld, attempt: 1},
        reveal: %{band: :meld}
      }

      socket = test_socket()
      result = Foley.push_foley_events(socket, old_room, new_room)

      refute Enum.any?(pushed_events(result), fn {name, _} -> name == "foley:ending" end)
    end
  end

  describe "push_foley_events/4 commit sound" do
    test "pushes foley:commit to stage view when count of committed seats rises" do
      stage_socket = test_socket(ThereishWeb.StageLive)

      old_room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: false},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      new_room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      socket = Foley.push_foley_events(stage_socket, old_room, new_room, stage?: true)
      assert pushed_events(socket) == [{"foley:commit", %{}}]
    end

    test "pushes foley:commit to stage view when phase transitions to assaying on last commit" do
      stage_socket = test_socket(ThereishWeb.StageLive)

      old_room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      new_room = %{
        phase: :assaying,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: true}
        ],
        speaker?: true
      }

      socket = Foley.push_foley_events(stage_socket, old_room, new_room, stage?: true)
      events = pushed_events(socket)
      assert {"foley:commit", %{}} in events
      assert {"foley:beat", %{}} in events
    end

    test "does not push foley:commit to stage when count does not rise" do
      stage_socket = test_socket(ThereishWeb.StageLive)

      room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      socket = Foley.push_foley_events(stage_socket, room, room, stage?: true)
      assert pushed_events(socket) == []
    end

    test "does not push foley:commit on initial mount (nil old_room)" do
      stage_socket = test_socket(ThereishWeb.StageLive)

      new_room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      socket = Foley.push_foley_events(stage_socket, nil, new_room, stage?: true)
      # On initial mount into bridging, it pushes page track, not commit
      events = pushed_events(socket)
      refute {"foley:commit", %{}} in events
    end

    test "does not push foley:commit across different attempts" do
      stage_socket = test_socket(ThereishWeb.StageLive)

      old_room = %{
        phase: :reveal,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: true}
        ],
        speaker?: true
      }

      new_room = %{
        phase: :bridging,
        attempt: %{number: 2, of: 5},
        seats: [
          %{id: "s1", committed?: false},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      socket = Foley.push_foley_events(stage_socket, old_room, new_room, stage?: true)
      events = pushed_events(socket)
      refute {"foley:commit", %{}} in events
    end

    test "never pushes foley:commit to phone views, even when holding speaker" do
      phone_socket = test_socket(ThereishWeb.RoomLive)

      old_room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: false},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      new_room = %{
        phase: :bridging,
        attempt: %{number: 1, of: 5},
        seats: [
          %{id: "s1", committed?: true},
          %{id: "s2", committed?: false}
        ],
        speaker?: true
      }

      socket = Foley.push_foley_events(phone_socket, old_room, new_room)
      events = pushed_events(socket)
      refute {"foley:commit", %{}} in events
    end
  end

  describe "push_foley_events/4 page track events" do
    test "pushes foley:page with track path, title, and kind: 'track' when room has landed track" do
      socket = test_socket()

      new_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        track: %{
          path: "/media/tracks/test.mp3",
          title: "Summer Camp · Viking Beaches"
        }
      }

      result = Foley.push_foley_events(socket, nil, new_room)
      events = pushed_events(result)

      assert {
               "foley:page",
               %{
                 path: "/media/tracks/test.mp3",
                 title: "Summer Camp · Viking Beaches",
                 kind: "track"
               }
             } in events
    end

    test "pushes foley:page when track lands over house loop" do
      socket = test_socket()
      loop = hd(Thereish.Foley.Loops.all())

      old_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        loop: loop,
        track: nil
      }

      new_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        loop: loop,
        track: %{
          path: "/media/tracks/test.mp3",
          title: "Summer Camp · Viking Beaches"
        }
      }

      result = Foley.push_foley_events(socket, old_room, new_room)
      events = pushed_events(result)

      assert {
               "foley:page",
               %{
                 path: "/media/tracks/test.mp3",
                 title: "Summer Camp · Viking Beaches",
                 kind: "track"
               }
             } in events
    end

    test "pushes foley:page when track title arrives after path" do
      socket = test_socket()

      old_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        track: %{
          path: "/media/tracks/test.mp3",
          title: nil
        }
      }

      new_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        track: %{
          path: "/media/tracks/test.mp3",
          title: "Summer Camp · Viking Beaches"
        }
      }

      result = Foley.push_foley_events(socket, old_room, new_room)
      events = pushed_events(result)

      assert {
               "foley:page",
               %{
                 path: "/media/tracks/test.mp3",
                 title: "Summer Camp · Viking Beaches",
                 kind: "track"
               }
             } in events
    end

    test "pushes foley:page with stream: true when playable early stream lands" do
      socket = test_socket()
      loop = hd(Thereish.Foley.Loops.all())

      old_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        loop: loop,
        track: nil
      }

      new_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        loop: loop,
        track: %{
          path: "https://stream.mureka.ai/live/stream123.aac",
          title: "Summer Camp · Viking Beaches",
          stream: true,
          format: :aac
        }
      }

      result = Foley.push_foley_events(socket, old_room, new_room)
      events = pushed_events(result)

      assert {
               "foley:page",
               %{
                 path: "https://stream.mureka.ai/live/stream123.aac",
                 title: "Summer Camp · Viking Beaches",
                 kind: "track",
                 stream: true
               }
             } in events
    end

    test "pushes foley:page when final track lands replacing stream" do
      socket = test_socket()

      old_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        track: %{
          path: "https://stream.mureka.ai/live/stream123.aac",
          title: "Summer Camp · Viking Beaches",
          stream: true,
          format: :aac
        }
      }

      new_room = %{
        phase: :bridging,
        speaker?: true,
        music: "page",
        track: %{
          path: "/media/tracks/final.mp3",
          title: "Summer Camp · Viking Beaches",
          format: :mp3
        }
      }

      result = Foley.push_foley_events(socket, old_room, new_room)
      events = pushed_events(result)

      assert {
               "foley:page",
               %{
                 path: "/media/tracks/final.mp3",
                 title: "Summer Camp · Viking Beaches",
                 kind: "track"
               }
             } in events
    end

    test "pushes Repertoire member when the waiting Stage claims the speaker" do
      first = hd(Thereish.Foley.Loops.all())
      socket = test_socket(ThereishWeb.StageLive)

      # Waiting snapshots have no Page loop yet; Foley falls back to the first shipped loop.
      new_room = %{
        phase: :waiting,
        speaker?: true,
        music: "house",
        loop: nil
      }

      result = Foley.push_foley_events(socket, nil, new_room, stage?: true)
      events = pushed_events(result)

      assert {"foley:page", %{path: first.path, title: first.name, kind: "repertoire"}} in events
    end

    test "pushes Repertoire member when music is switched from off to house while waiting" do
      first = hd(Thereish.Foley.Loops.all())
      socket = test_socket(ThereishWeb.StageLive)

      old_room = %{
        phase: :waiting,
        speaker?: true,
        music: "off",
        loop: nil
      }

      new_room = %{
        phase: :waiting,
        speaker?: true,
        music: "house",
        loop: nil
      }

      result = Foley.push_foley_events(socket, old_room, new_room, stage?: true)
      events = pushed_events(result)

      assert {"foley:page", %{path: first.path, title: first.name, kind: "repertoire"}} in events
    end

    test "pushes Repertoire draw during giving and writing when room has no landed track" do
      socket = test_socket()

      giving_room = %{
        phase: :giving,
        speaker?: true,
        music: "page",
        playing: %{path: "/audio/house-loop-2.mp3", title: "Sunlit Drift", kind: "repertoire"}
      }

      result = Foley.push_foley_events(socket, nil, giving_room)
      events = pushed_events(result)

      assert {"foley:page",
              %{path: "/audio/house-loop-2.mp3", title: "Sunlit Drift", kind: "repertoire"}} in events

      # Transition to writing keeps the wait music without spurious push
      writing_room = %{giving_room | phase: :writing}
      result_writing = Foley.push_foley_events(socket, giving_room, writing_room)
      refute Enum.any?(pushed_events(result_writing), fn {name, _} -> name == "foley:page" end)
    end

    test "pushes holdover during giving and writing, and pushes new track when it lands during writing" do
      socket = test_socket()

      giving_room = %{
        phase: :giving,
        speaker?: true,
        music: "page",
        track: %{path: "/media/tracks/p1.mp3", title: "Previous Track"},
        playing: %{path: "/media/tracks/p1.mp3", title: "Previous Track", kind: "holdover"}
      }

      result = Foley.push_foley_events(socket, nil, giving_room)
      events = pushed_events(result)

      assert {"foley:page",
              %{path: "/media/tracks/p1.mp3", title: "Previous Track", kind: "holdover"}} in events

      # Transition to writing keeps the holdover track without spurious push
      writing_room = %{giving_room | phase: :writing}
      result_writing = Foley.push_foley_events(socket, giving_room, writing_room)
      refute Enum.any?(pushed_events(result_writing), fn {name, _} -> name == "foley:page" end)

      # When new page's track lands during writing, foley:page seizes the speaker with kind: "track"
      landed_room = %{
        writing_room
        | track: %{path: "/media/tracks/p2.mp3", title: "New Track"},
          playing: %{path: "/media/tracks/p2.mp3", title: "New Track", kind: "track"}
      }

      result_landed = Foley.push_foley_events(socket, writing_room, landed_room)
      events_landed = pushed_events(result_landed)

      assert {"foley:page", %{path: "/media/tracks/p2.mp3", title: "New Track", kind: "track"}} in events_landed
    end
  end

  describe "push_own_commit/1" do
    test "pushes foley:own-commit when no stage is present" do
      socket = test_socket() |> Phoenix.Component.assign(:stage_present?, false)
      result = Foley.push_own_commit(socket)
      assert {"foley:own-commit", %{}} in pushed_events(result)
    end

    test "does not push foley:own-commit when stage is present" do
      socket = test_socket() |> Phoenix.Component.assign(:stage_present?, true)
      result = Foley.push_own_commit(socket)
      assert pushed_events(result) == []
    end
  end
end
