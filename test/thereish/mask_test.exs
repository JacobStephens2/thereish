defmodule Thereish.MaskTest do
  @moduledoc """
  A Mask has one shape from the Limner's draw to the Chronicle: a `%Mask{}` when
  it was drawn, `:dot` when it was not (ticket 197).
  """
  use Thereish.DataCase, async: false

  import ExUnit.CaptureLog

  alias Thereish.Mask

  @give "lighthouse"
  @colour "#c45c26"

  defp fake_draw(settings) do
    steward = Application.get_env(:thereish, :steward, [])
    fake = steward[:fake] || []
    Application.put_env(:thereish, :steward, Keyword.put(steward, :fake, settings ++ fake))
    on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)
  end

  describe "draw/2" do
    test "a drawn Mask is its URL and meta, without the bytes" do
      fake_draw(draw_capture: self())

      assert %Mask{url: url, meta: meta} = Mask.draw(@give, @colour)
      assert "/media/masks/" <> _ = url
      assert meta.provider == "fake"
      assert meta.model == "fake-limner"
      refute Map.has_key?(meta, :bytes)

      assert_receive {:draw, @give, @colour, opts}
      assert opts[:size] == 512
    end

    test "a refusal is the dot, logged" do
      fake_draw(draw_mode: :refused)

      log = capture_log(fn -> assert Mask.draw("murder", @colour) == :dot end)
      assert log =~ "Limner draw failed"
      assert log =~ ":refused"
    end

    test "an unavailable Limner is the dot" do
      fake_draw(draw_mode: :unavailable)

      capture_log(fn -> assert Mask.draw(@give, @colour) == :dot end)
    end

    test "a timeout is the dot" do
      fake_draw(draw_mode: :timeout)

      capture_log(fn -> assert Mask.draw(@give, @colour) == :dot end)
    end

    test "a Limner that raises is the dot, not a crash" do
      fake_draw(draw_mode: :raise)

      log = capture_log(fn -> assert Mask.draw(@give, @colour) == :dot end)
      assert log =~ "Limner draw crashed"
    end
  end

  describe "url/1" do
    test "a Mask's URL, and nil for anything that is not a Mask" do
      assert Mask.url(%Mask{url: "/media/masks/a.png", meta: %{}}) == "/media/masks/a.png"
      assert Mask.url(:dot) == nil
      assert Mask.url(:face_down) == nil
      assert Mask.url(nil) == nil
      assert Mask.url(%{"url" => "/media/masks/a.png"}) == nil
    end
  end

  describe "as an Ecto.Type" do
    test "a Mask and the dot round-trip through dump and load" do
      mask = %Mask{url: "/media/masks/a.png", meta: %{"model" => "fake-limner"}}

      assert {:ok, dumped} = Ecto.Type.dump(Mask, mask)
      assert dumped == %{"url" => "/media/masks/a.png", "meta" => %{"model" => "fake-limner"}}
      assert Ecto.Type.load(Mask, dumped) == {:ok, mask}

      assert Ecto.Type.dump(Mask, :dot) == {:ok, "dot"}
      assert Ecto.Type.load(Mask, "dot") == {:ok, :dot}
    end

    test "a Page's masks are stored and read back as Masks" do
      mask = %Mask{url: "/media/masks/a.png", meta: %{model: "fake-limner", cost_usd: 0.04}}
      types = %{masks: {:map, Mask}}

      assert {:ok, dumped} = Ecto.Type.dump(types.masks, %{"s1" => mask, "s2" => :dot})
      json = dumped |> Jason.encode!() |> Jason.decode!()

      assert {:ok, %{"s1" => loaded, "s2" => :dot}} = Ecto.Type.load(types.masks, json)
      assert loaded.url == "/media/masks/a.png"
      assert loaded.meta == %{"model" => "fake-limner", "cost_usd" => 0.04}
    end

    test "loads a stored row with string keys" do
      row = %{
        "url" => "/media/masks/a.png",
        "path" => "/media/masks/a.png",
        "meta" => %{"model" => "m"}
      }

      assert Ecto.Type.load(Mask, row) ==
               {:ok, %Mask{url: "/media/masks/a.png", meta: %{"model" => "m"}}}
    end

    test "loads a row with atom keys" do
      row = %{url: "/media/masks/a.png", meta: %{model: "m"}}

      assert Ecto.Type.load(Mask, row) ==
               {:ok, %Mask{url: "/media/masks/a.png", meta: %{model: "m"}}}
    end

    test "a row with no meta keeps its other fields as meta" do
      row = %{"url" => "/media/masks/a.png", "path" => "/x", "model" => "m", "cost_usd" => 0.04}

      assert Ecto.Type.load(Mask, row) ==
               {:ok,
                %Mask{url: "/media/masks/a.png", meta: %{"model" => "m", "cost_usd" => 0.04}}}
    end

    test "stored bytes are dropped on load" do
      row = %{"url" => "/media/masks/a.png", "bytes" => "PNG", "meta" => %{"model" => "m"}}

      assert {:ok, %Mask{} = mask} = Ecto.Type.load(Mask, row)
      assert mask == %Mask{url: "/media/masks/a.png", meta: %{"model" => "m"}}
    end

    test "casts only a Mask or the dot" do
      mask = %Mask{url: "/media/masks/a.png", meta: %{}}

      assert Ecto.Type.cast(Mask, mask) == {:ok, mask}
      assert Ecto.Type.cast(Mask, :dot) == {:ok, :dot}
      assert Ecto.Type.cast(Mask, %{"url" => "/media/masks/a.png"}) == :error
    end
  end
end
