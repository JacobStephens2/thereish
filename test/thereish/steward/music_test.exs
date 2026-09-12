defmodule Thereish.Steward.MusicTest do
  @moduledoc """
  Generation-request construction for Foley Tracks and Vamps (ticket 07, #138).

  Ordinary tests inspect the brief. Model output quality is a listening judgment,
  not an exact-output assertion or a paid call.
  """
  use ExUnit.Case, async: true

  alias Thereish.Steward.Music

  describe "prompt/1" do
    test "a heavy-metal Give drives genre, instrumentation, and energy rather than a gentle background" do
      prompt = Music.prompt(["Kiss Heavy Metal"])

      assert prompt =~ "Kiss Heavy Metal"
      assert_drives_genre_and_energy(prompt)
      refute_gentle_background(prompt)
      assert prompt =~ ~r/instrumental/i
      assert prompt =~ ~r/volume/i
    end

    test "a nonmusical Give supplies atmosphere rather than flattening composition" do
      prompt = Music.prompt(["alpine meadow"])

      assert prompt =~ "alpine meadow"
      assert prompt =~ ~r/atmosphere/i
      refute_gentle_background(prompt)
    end

    test "conflicting musical Gives invite a fusion rather than a common subdued style" do
      prompt = Music.prompt(["Kiss Heavy Metal", "bossa nova"])

      assert prompt =~ "Kiss Heavy Metal"
      assert prompt =~ "bossa nova"
      assert prompt =~ ~r/fuse/i
      refute_gentle_background(prompt)
    end

    test "comfortable playback volume is mix, not a requirement for gentle composition" do
      prompt = Music.prompt(["Kiss Heavy Metal"])

      assert prompt =~ ~r/volume/i
      refute prompt =~ "Gentle, conversational background"
      refute prompt =~ "Soft and gentle"
    end
  end

  describe "vamp_prompt/1" do
    test "a heavy-metal Give drives genre and energy on the Vamp without asking for speech" do
      prompt = Music.vamp_prompt(["Kiss Heavy Metal"])

      assert prompt =~ "Kiss Heavy Metal"
      assert_drives_genre_and_energy(prompt)
      refute_gentle_background(prompt)
      assert prompt =~ ~r/instrumental/i
      refute prompt =~ "conversational"
      refute prompt =~ "spoken conversation"
      assert String.starts_with?(prompt, Music.vamp_prefix())
    end

    test "a nonmusical Give supplies atmosphere on the Vamp" do
      prompt = Music.vamp_prompt(["alpine meadow"])

      assert prompt =~ "alpine meadow"
      assert prompt =~ ~r/atmosphere/i
      refute_gentle_background(prompt)
      refute prompt =~ "conversational"
      refute prompt =~ "spoken conversation"
    end

    test "conflicting musical Gives invite a fusion on the Vamp" do
      prompt = Music.vamp_prompt(["Kiss Heavy Metal", "bossa nova"])

      assert prompt =~ "Kiss Heavy Metal"
      assert prompt =~ "bossa nova"
      assert prompt =~ ~r/fuse/i
      refute_gentle_background(prompt)
      refute prompt =~ "conversational"
      refute prompt =~ "spoken conversation"
    end
  end

  defp assert_drives_genre_and_energy(prompt) do
    assert prompt =~ ~r/genre/i
    assert prompt =~ ~r/instrumentation/i
    assert prompt =~ ~r/energy/i
  end

  defp refute_gentle_background(prompt) do
    refute prompt =~ "Gentle, conversational background"
    refute prompt =~ "Soft and gentle"
    refute prompt =~ "Atmosphere and theme:"
  end
end
