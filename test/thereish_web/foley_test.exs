defmodule ThereishWeb.FoleyTest do
  @moduledoc """
  How each Cue reaches the browser, and the two pushes that are not Cues: a
  Voice clip and the committing phone's own tick. When a Cue plays is
  `Thereish.Foley.CuesTest`'s business.
  """
  use ExUnit.Case, async: true

  alias ThereishWeb.Foley
  alias Phoenix.LiveView.Socket

  defp test_socket do
    %Socket{
      endpoint: ThereishWeb.Endpoint,
      view: ThereishWeb.RoomLive,
      private: %{live_temp: %{}}
    }
  end

  defp pushed_events(socket) do
    socket
    |> Phoenix.LiveView.Utils.get_push_events()
    |> Enum.map(fn [event, payload | _] -> {event, payload} end)
  end

  describe "event/1" do
    test "each Cue becomes the event and payload the browser's Foley hook listens for" do
      assert Foley.event(:stop) == {"foley:stop", %{}}
      assert Foley.event({:stop_voice, 2}) == {"foley:stop_voice", %{attempt: 2}}

      assert Foley.event({:page, "/media/tracks/p1.mp3", "Summer Camp", "track"}) ==
               {"foley:page",
                %{path: "/media/tracks/p1.mp3", title: "Summer Camp", kind: "track"}}

      assert Foley.event({:page, nil, nil, nil}) ==
               {"foley:page", %{path: nil, title: nil, kind: nil}}

      assert Foley.event(:beat) == {"foley:beat", %{}}
      assert Foley.event({:sting, :miss}) == {"foley:sting", %{band: :miss}}
      assert Foley.event({:ending, :deep_meld}) == {"foley:ending", %{kind: :deep_meld}}

      assert Foley.event({:prologue, "/audio/prologue-2.mp3"}) ==
               {"foley:prologue", %{path: "/audio/prologue-2.mp3"}}

      assert Foley.event(:stop_prologue) == {"foley:stop_prologue", %{}}
      assert Foley.event(:commit) == {"foley:commit", %{}}
    end
  end

  describe "push_voice/3" do
    defp speaking_socket do
      test_socket()
      |> Phoenix.Component.assign(:slug, "dust")
      |> Phoenix.Component.assign(:room, %{speaker?: true})
    end

    test "pushes Bookends speech to the speaker with a bookends url" do
      socket = Foley.push_voice(speaking_socket(), 1, :bookends)

      assert {"foley:voice", %{attempt: 1, kind: "bookends", url: "/r/dust/voice/1/bookends"}} in pushed_events(
               socket
             )
    end

    test "pushes verdict speech to the speaker with the attempt url" do
      socket = Foley.push_voice(speaking_socket(), 2, :verdict)

      assert {"foley:voice", %{attempt: 2, kind: "verdict", url: "/r/dust/voice/2"}} in pushed_events(
               socket
             )
    end

    test "does not push voice to a non-speaker" do
      socket =
        test_socket()
        |> Phoenix.Component.assign(:slug, "dust")
        |> Phoenix.Component.assign(:room, %{speaker?: false})

      result = Foley.push_voice(socket, 1, :bookends)
      assert pushed_events(result) == []
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
