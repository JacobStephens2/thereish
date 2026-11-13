defmodule ThereishWeb.RevealSequenceTest do
  use ExUnit.Case, async: true
  import Thereish.RevealFixtures
  import Phoenix.LiveViewTest

  test "the real adapter respects Pacing's deadlines and mounted lifetime" do
    rooms =
      for count <- 2..Thereish.Steward.seat_cap(),
          opts <- [
            [],
            [split: true],
            [calls: true],
            [closeness: 95],
            [ungraded: true],
            [split: true, calls: true, sequence: [stagger: 1, cap: 2, settle: 1]]
          ] do
        perform([count: count] ++ opts).room
      end

    rooms = rooms ++ [perform(sequence: []).room]

    path =
      Path.join(System.tmp_dir!(), "reveal-schedules-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(rooms))
    on_exit(fn -> File.rm!(path) end)

    {output, status} =
      System.cmd("node", ["test/support/reveal_sequence.cjs", path], stderr_to_stdout: true)

    assert status == 0, "Node exited with #{status}: #{output}"
    assert output =~ "REVEAL_TESTS_PASSED"
  end

  test "phone, Stage and quiet phone consume the same stored schedule" do
    %{room: room, pacing: pacing, game: game} = perform(split: true, calls: true)
    resumed = snapshot(pacing, game, 750)

    for mode <- [:phone, :stage, :quiet], snapshot <- [room, resumed] do
      html = render_component(&ThereishWeb.RoomComponents.reveal/1, room: snapshot, mode: mode)

      encoded =
        snapshot.reveal_sequence
        |> Jason.encode!()
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s(data-sequence="#{encoded}")
    end
  end
end
