defmodule MeaningGameWeb.FoleyTest do
  use MeaningGameWeb.ConnCase, async: true

  alias MeaningGameWeb.Foley

  defp pushed_events(socket) do
    (socket.private[:live_temp] && socket.private.live_temp[:push_events]) || []
  end

  describe "push_foley_events/3 ending events" do
    test "pushes :meld when closed because of meld with meld band" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld, attempt: 1},
        reveal: %{band: :meld}
      }

      socket = %Phoenix.LiveView.Socket{}
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert ["foley:ending", %{kind: :meld}] in pushed_events(result)
    end

    test "pushes :deep_meld when closed because of meld with deep_meld band" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld, attempt: 1},
        reveal: %{band: :deep_meld}
      }

      socket = %Phoenix.LiveView.Socket{}
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert ["foley:ending", %{kind: :deep_meld}] in pushed_events(result)
    end

    test "pushes :unmelded when closed because of attempts_spent" do
      old_room = %{phase: :reveal, speaker?: true}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :attempts_spent, attempt: 5},
        reveal: %{band: :miss}
      }

      socket = %Phoenix.LiveView.Socket{}
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert ["foley:ending", %{kind: :unmelded}] in pushed_events(result)
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

      socket = %Phoenix.LiveView.Socket{}
      result = Foley.push_foley_events(socket, old_room, new_room)

      assert ["foley:ending", %{kind: :deep_meld}] in pushed_events(result)
    end

    test "does not push ending when already closed" do
      old_room = %{phase: :closed, speaker?: true, closed: %{because: :meld}}

      new_room = %{
        phase: :closed,
        speaker?: true,
        closed: %{because: :meld},
        reveal: %{band: :meld}
      }

      socket = %Phoenix.LiveView.Socket{}
      result = Foley.push_foley_events(socket, old_room, new_room)

      refute Enum.any?(pushed_events(result), fn [name | _] -> name == "foley:ending" end)
    end

    test "does not push ending to non-speaker" do
      old_room = %{phase: :reveal, speaker?: false}

      new_room = %{
        phase: :closed,
        speaker?: false,
        closed: %{because: :meld, attempt: 1},
        reveal: %{band: :meld}
      }

      socket = %Phoenix.LiveView.Socket{}
      result = Foley.push_foley_events(socket, old_room, new_room)

      refute Enum.any?(pushed_events(result), fn [name | _] -> name == "foley:ending" end)
    end
  end
end
