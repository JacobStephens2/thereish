defmodule MeaningGameWeb.FoleyTest do
  use ExUnit.Case, async: true

  alias MeaningGameWeb.Foley
  alias Phoenix.LiveView.Socket

  defp test_socket(view) do
    %Socket{
      endpoint: MeaningGameWeb.Endpoint,
      view: view,
      private: %{live_temp: %{}}
    }
  end

  defp pushed_events(socket) do
    socket
    |> Phoenix.LiveView.Utils.get_push_events()
    |> Enum.map(fn [event, payload | _] -> {event, payload} end)
  end

  describe "push_foley_events/4 commit sound" do
    test "pushes foley:commit to stage view when count of committed seats rises" do
      stage_socket = test_socket(MeaningGameWeb.StageLive)

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
      stage_socket = test_socket(MeaningGameWeb.StageLive)

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
      stage_socket = test_socket(MeaningGameWeb.StageLive)

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
      stage_socket = test_socket(MeaningGameWeb.StageLive)

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
      stage_socket = test_socket(MeaningGameWeb.StageLive)

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
      phone_socket = test_socket(MeaningGameWeb.RoomLive)

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
end
