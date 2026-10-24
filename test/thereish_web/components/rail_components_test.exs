defmodule ThereishWeb.RailComponentsTest do
  @moduledoc """
  The Rail is the Ladder's only drawing, so every test here asks the same
  question: does the picture say what the configuration says?

  The scale is global configuration, which is why this file is not async: the
  width test moves the Ladder underneath the component and puts it back.
  """
  use ThereishWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import ThereishWeb.RailComponents

  alias Thereish.Ladder

  defp rail(assigns) do
    render_component(&ladder_rail/1, Keyword.put_new(assigns, :mode, :phone))
  end

  # The widths the markup actually carries, band by band, in order.
  defp widths(html) do
    for [_, band, width] <- Regex.scan(~r/data-band="(\w+)"\s+style="width: ([\d.]+)%"/, html),
        do: {band, width}
  end

  defp ladder(bands, scale) do
    previous = Application.fetch_env!(:thereish, :ladder)
    on_exit(fn -> Application.put_env(:thereish, :ladder, previous) end)

    Application.put_env(:thereish, :ladder, scale: scale, bands: bands)
  end

  describe "the bands" do
    test "draws one band per configured band, in order, each named" do
      html = rail(closeness: 61, band: :close, melded?: false)

      for band <- Ladder.band_names() do
        assert html =~ ~s(data-role="rail-band")
        assert html =~ ~s(data-band="#{band}")
      end

      assert length(Regex.scan(~r/data-role="rail-band"/, html)) ==
               length(Ladder.band_names())
    end

    test "each band is as wide as the span it owns, whatever the Ladder says" do
      ladder([miss: 0, adjacent: 20, close: 60, meld: 90], 0..100)

      assert widths(rail(closeness: 61, band: :close)) == [
               {"miss", "20"},
               {"adjacent", "40"},
               {"close", "30"},
               {"meld", "10"}
             ]
    end

    test "a scale that is not nought to a hundred is still drawn as one width" do
      ladder([miss: 0, close: 25, meld: 40], 0..50)

      assert widths(rail(closeness: 41, band: :meld)) == [
               {"miss", "50"},
               {"close", "30"},
               {"meld", "20"}
             ]
    end

    test "the Meld line stands where a Meld starts and says so" do
      html = rail(closeness: 61, band: :close)

      assert html =~ ~s(data-role="meld-line")
      assert html =~ ~s(style="left: #{Ladder.meld_threshold()}%")
      assert html =~ "Meld"
    end
  end

  describe "the marker" do
    test "stands at the grade, and carries it for the sequencer to launch it from" do
      html = rail(closeness: 83, band: :almost, gap: 7)

      assert html =~ ~s(data-role="rail-marker")
      assert html =~ ~s(data-target="83")
      assert html =~ ~s(style="left: 83%")
    end

    test "an Attempt the Assayer could not grade draws the scale and no marker" do
      html = rail(closeness: nil, band: nil)

      assert html =~ ~s(data-role="rail-band")
      refute html =~ ~s(data-role="rail-marker")
    end
  end

  describe "how short it fell" do
    test "says the gap in words at seven short of a Meld" do
      html = rail(closeness: 83, band: :almost, gap: 7)

      assert html =~ ~s(data-role="short-by")
      assert html =~ "seven short"
    end

    test "says nothing on a Meld, on an ungraded Attempt, or from a long way out" do
      for assigns <- [
            [closeness: 94, band: :meld, melded?: true, gap: nil],
            [closeness: nil, band: nil, gap: nil],
            [closeness: 40, band: :adjacent, gap: 50]
          ] do
        refute rail(assigns) =~ ~s(data-role="short-by")
      end
    end
  end

  describe "the Call pins" do
    test "one pin per Call, in its Seat's colour, in the middle of the band it named" do
      calls = [
        %{seat_id: "s1", name: "Mara", band: :close, colour: "#e11d48"},
        %{seat_id: "s2", name: "Bram", band: :meld, colour: "#2563eb"}
      ]

      html = rail(closeness: 61, band: :close, calls: calls)

      assert length(Regex.scan(~r/data-role="call-pin"/, html)) == 2
      assert html =~ ~s(data-seat="s1")
      assert html =~ "--seat-color: #e11d48"
      assert html =~ "--seat-color: #2563eb"
      assert html =~ "Mara called close"
      assert html =~ ~s(left: #{band_midpoint(:close)}%)
      assert html =~ ~s(left: #{band_midpoint(:meld)}%)
    end

    test "a pin sits in the middle of its band and nowhere else" do
      assert band_midpoint(:close) == "65"
      assert band_midpoint(:meld) == "95"
    end

    test "a Call whose Seat has no colour wears the house colour" do
      html =
        rail(closeness: 61, band: :close, calls: [%{seat_id: "s1", name: "Sid", band: :miss}])

      assert html =~ "--seat-color: var(--color-primary, currentColor)"
    end

    test "no Calls is no pins" do
      refute rail(closeness: 61, band: :close) =~ ~s(data-role="call-pin")
    end
  end

  describe "the ghost pins" do
    test "a mark is drawn where it reads, wearing its label" do
      html = rail(closeness: 61, band: :close, marks: [%{closeness: 31, label: "forward"}])

      assert html =~ ~s(data-role="rail-mark")
      assert html =~ ~s(style="left: 31%")
      assert html =~ "forward"
    end
  end

  describe "both screens" do
    test "the Rail is drawn on the phone, on the Stage, and on a quiet phone" do
      for mode <- [:phone, :stage, :quiet] do
        html = rail(mode: mode, closeness: 83, band: :almost, gap: 7)

        assert html =~ ~s(data-role="ladder-rail")
        assert html =~ ~s(data-mode="#{mode}")
        assert html =~ ~s(data-role="short-by")
      end
    end
  end
end
