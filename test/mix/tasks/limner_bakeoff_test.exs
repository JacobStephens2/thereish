defmodule Mix.Tasks.Limner.BakeoffTest do
  @moduledoc """
  Tests for `mix limner.bakeoff` (ticket 84). Against the Fake, no network.
  """
  use Thereish.DataCase, async: false

  alias Mix.Tasks.Limner.Bakeoff
  alias Thereish.Steward.Limner

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "limner-bakeoff-test-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(tmp_dir) end)

    %{dir: tmp_dir}
  end

  test "writes a contact sheet and timing table per vendor without a network", %{dir: dir} do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Bakeoff.run(["--dir", dir, "--fake"])
      end)

    assert output =~ dir
    assert output =~ "LIMNER BAKE-OFF"

    vendors = ["recraft", "ideogram", "bfl"]
    gives = Limner.bakeoff_gives()

    assert Enum.any?(gives, fn {give, _} -> give == "murder" end)
    assert Enum.any?(gives, fn {give, _} -> give == "Vecna" end)

    for vendor <- vendors do
      vendor_dir = Path.join(dir, vendor)
      assert File.dir?(vendor_dir), "Expected #{vendor_dir} to exist"

      sheet = Path.join(vendor_dir, "contact-sheet.html")
      assert File.exists?(sheet), "Expected #{sheet} to exist"
      html = File.read!(sheet)
      assert html =~ "murder"
      assert html =~ "Vecna"
      assert html =~ "ms"

      for {_give, _colour} <- gives do
        # At least one PNG per Give
        pngs = Path.wildcard(Path.join(vendor_dir, "*.png"))
        assert length(pngs) == length(gives)
      end
    end

    report_txt = Path.join(dir, "report.txt")
    report_json = Path.join(dir, "report.json")
    assert File.exists?(report_txt)
    assert File.exists?(report_json)

    report = Jason.decode!(File.read!(report_json))
    assert length(report["gives"]) == 6
    assert "murder" in report["gives"]
    assert "Vecna" in report["gives"]

    for vendor <- vendors do
      rows = report["vendors"][vendor]
      assert is_list(rows)
      assert length(rows) == 6

      for row <- rows do
        assert is_number(row["latency_ms"])
        assert row["status"] in ["ok", "refused", "failed"]
      end
    end

    txt = File.read!(report_txt)
    assert txt =~ "Recraft"
    assert txt =~ "Ideogram"
    assert txt =~ "BFL"
    assert txt =~ "ms"
  end
end
