defmodule Mix.Tasks.Calibration.ExportTest do
  @moduledoc """
  Tests for `mix calibration.export` (ticket 11, ADR-0005).
  """
  use Thereish.DataCase, async: false

  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Rooms
  alias Thereish.Rooms.Room

  setup do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    :ok = Rooms.give(slug, melissa.id, "setting one")
    :ok = Rooms.give(slug, jacob.id, "setting two")
    await_phase(slug, :bridging)

    :ok = Rooms.commit_bridge(slug, melissa.id, "cairn")
    :ok = Rooms.commit_bridge(slug, jacob.id, "cairo")
    await_reveal(slug)

    room = Repo.get_by!(Room, slug: slug)

    {:ok, _} =
      Chronicle.record_fairness_tap(room.id, %{
        seat_id: melissa.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      })

    %{slug: slug, melissa: melissa, jacob: jacob}
  end

  test "exports calibration dataset to stdout in json", %{slug: slug} do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Calibration.Export.run(["--room", slug])
      end)

    assert {:ok, parsed} = Jason.decode(output)
    assert length(parsed) == 1
    assert hd(parsed)["label"] == "fair"
    assert hd(parsed)["bookends"] == ["lantern", "harbour"]
    assert hd(parsed)["grade"] == 80
  end

  test "exports each Seat's current opinion only, without the admin's reviews", ctx do
    room = Repo.get_by!(Room, slug: ctx.slug)

    for attrs <- [
          %{seat_id: ctx.melissa.id, label: "too_kind"},
          %{source: "admin", admin_id: Thereish.AdminFixtures.identity().id, label: "too_harsh"}
        ] do
      {:ok, _} =
        Chronicle.record_fairness_tap(
          room.id,
          Map.merge(
            %{attempt_number: 1, bookends: ["lantern", "harbour"], bridges: ["cairn", "cairo"]},
            attrs
          )
        )
    end

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.Calibration.Export.run(["--room", ctx.slug])
      end)

    assert [%{"label" => "too_kind", "seat_id" => seat_id}] = Jason.decode!(output)
    assert seat_id == ctx.melissa.id
  end

  test "exports calibration dataset to a file in jsonl format", %{slug: slug} do
    tmp_path =
      Path.join(System.tmp_dir!(), "calibration-test-#{System.unique_integer([:positive])}.jsonl")

    on_exit(fn -> File.rm(tmp_path) end)

    ExUnit.CaptureIO.capture_io(fn ->
      Mix.Tasks.Calibration.Export.run([
        "--room",
        slug,
        "--format",
        "jsonl",
        "--output",
        tmp_path
      ])
    end)

    assert File.exists?(tmp_path)
    content = File.read!(tmp_path)
    assert content =~ ~s("label":"fair")
    assert content =~ ~s("grade":80)
  end
end
