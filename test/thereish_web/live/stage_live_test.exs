defmodule ThereishWeb.StageLiveTest do
  @moduledoc """
  The laptop on the table, holding no Seat.

  What the Stage does with the Room's new public words: a Nudge landing is
  theatre under the Bookends, and the Calls are a row anyone behind the couch
  can read. The phones' side of both lives in `ThereishWeb.RoomLiveTest`.
  """
  use ThereishWeb.ConnCase, async: false

  import Thereish.RoomFixtures
  import Phoenix.LiveViewTest

  defp phone(slug), do: build_conn() |> get(~p"/r/#{slug}")

  defp join(view, name),
    do: view |> form("form[phx-submit=join]", %{"name" => name}) |> render_submit()

  defp give_setting(view, give),
    do: view |> form("[data-role=setting-form]", %{"give" => give}) |> render_submit()

  defp commit(view, bridge),
    do: view |> form("[data-role=bridge-form]", %{"bridge" => bridge}) |> render_submit()

  defp nudge(view, word),
    do: view |> form("[data-role=nudge-form]", %{"nudge" => word}) |> render_submit()

  defp couch(slug) do
    {:ok, mara, _} = live(phone(slug))
    {:ok, esme, _} = live(phone(slug))
    {:ok, stage, _} = live(build_conn(), ~p"/r/#{slug}/stage")

    join(mara, "Mara")
    join(esme, "Esme")

    give_setting(mara, "lanterns on the quay")
    give_setting(esme, "fog over the harbour")
    await_phase(slug, :bridging)

    eventually(fn -> has_element?(mara, "[data-role=bridge-form]") end)
    eventually(fn -> has_element?(esme, "[data-role=bridge-form]") end)

    %{mara: mara, esme: esme, stage: stage}
  end

  describe "the Nudge on the Stage (T4)" do
    test "a landed Nudge is theatre under the Bookends, and says whose it is" do
      slug = open_room()
      %{mara: mara, stage: stage} = couch(slug)

      refute has_element?(stage, "[data-role=nudges]")

      nudge(mara, "rope")

      eventually(fn -> has_element?(stage, "[data-role=nudge-chip]", "rope") end)
      assert has_element?(stage, "[data-role=nudges-caption]", "Nudges")
      assert has_element?(stage, "[data-role=nudge-by]", "Mara nudges")
      assert has_element?(stage, "[data-role=nudge-spent]", "Spent")

      html = render(stage)
      {bookends_at, _} = :binary.match(html, ~s(data-role="bookends"))
      {nudges_at, _} = :binary.match(html, ~s(data-role="nudges"))

      assert bookends_at < nudges_at
    end
  end

  describe "the Calls on the Stage (T4)" do
    test "the Beat's Calls are a read-only row, with nothing to tap" do
      beat(1_000)

      slug = open_room()
      %{mara: mara, esme: esme, stage: stage} = couch(slug)

      commit(mara, "cairn")
      commit(esme, "cairo")

      assert has_element?(stage, "[data-role=beat-meter]")
      refute has_element?(stage, "[data-role=call-row]")

      mara |> element("[data-role=call-band][data-band=close]") |> render_click()

      eventually(fn -> has_element?(stage, "[data-role=call-row]") end)
      assert has_element?(stage, "[data-role=called][data-band=close]", "Mara called")
      refute has_element?(stage, "[data-role=call-band]")
      refute has_element?(stage, "[data-role=call-caption]")
    end
  end
end
