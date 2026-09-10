defmodule Thereish.Steward.LimnerTest do
  @moduledoc """
  The Fake Limner answers `draw`: one Give and a Seat's colour in, image bytes
  out, with measured metadata and spend (ticket 84).
  """
  use Thereish.DataCase, async: false

  alias Thereish.Steward
  alias Thereish.Steward.Fake
  alias Thereish.Steward.Limner

  @give "lighthouse"
  @colour "#c45c26"

  describe "Steward.draw with Fake adapter" do
    test "answers PNG bytes, format, and measured metadata including spend" do
      assert {:ok, mask} = Steward.draw(@give, @colour)

      assert mask.format == :png
      assert is_binary(mask.bytes)
      assert png?(mask.bytes)
      assert mask.meta.provider == "fake"
      assert mask.meta.model == "fake-limner"
      assert is_number(mask.meta.cost_usd)
      assert is_integer(mask.meta.latency_ms)
      assert mask.meta.latency_ms >= 0
    end

    test "the Fake answers draw with the Seat's colour in the picture" do
      assert {:ok, mask} = Fake.draw(@give, @colour)
      assert png?(mask.bytes)
      assert mask.format == :png
    end

    test "a dark Give the Fake is set to refuse is a refusal, not a crash" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          Keyword.put(fake_config, :draw_mode, :refused)
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      assert {:error, :refused} = Steward.draw("murder", "#7a1f1f")
    end

    test "a refusal retries once with a softened prompt and stops on second failure" do
      fake_config = Application.get_env(:thereish, :steward, [])[:fake] || []

      Application.put_env(
        :thereish,
        :steward,
        Keyword.put(
          Application.get_env(:thereish, :steward, []),
          :fake,
          fake_config
          |> Keyword.put(:draw_mode, :refused)
          |> Keyword.put(:draw_capture, self())
        )
      )

      on_exit(fn ->
        Application.put_env(
          :thereish,
          :steward,
          Keyword.put(Application.get_env(:thereish, :steward, []), :fake, fake_config)
        )
      end)

      assert {:error, :refused} = Steward.draw("murder", "#7a1f1f")

      assert_receive {:draw, "murder", "#7a1f1f", first_opts}
      refute Keyword.get(first_opts, :softened, false)

      assert_receive {:draw, "murder", "#7a1f1f", second_opts}
      assert Keyword.get(second_opts, :softened, false)

      refute_receive {:draw, _, _, _}
    end
  end

  describe "Limner prompt" do
    test "names the Give and the Seat's colour and describes the house style without a painter's name" do
      prompt = Limner.prompt(@give, @colour)

      assert prompt =~ @give
      assert prompt =~ @colour
      assert prompt =~ "ochre"
      assert prompt =~ "overlapping planes"
      refute prompt =~ "Picasso"
    end

    test "softened prompt softens the Give for safety retry" do
      prompt = Limner.prompt(@give, @colour, softened: true)

      assert prompt =~ @give
      assert prompt =~ @colour
      assert prompt =~ "Softened"
    end
  end

  defp png?(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: true
  defp png?(_), do: false
end
