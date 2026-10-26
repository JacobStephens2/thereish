defmodule Thereish.Steward.MusicTest do
  @moduledoc """
  Generation-request construction for Foley Tracks and Vamps (ticket 07, #138).

  Ordinary tests inspect the brief. Model output quality is a listening judgment,
  not an exact-output assertion or a paid call.
  """
  use ExUnit.Case, async: true

  alias Thereish.Steward.Music

  describe "prompt/1 and vamp_prompt/1" do
    test "a heavy-metal Give drives genre, instrumentation, and energy rather than a gentle background" do
      for prompt <- briefs(["Kiss Heavy Metal"]) do
        assert prompt =~ "Kiss Heavy Metal"
        assert_drives_genre_and_energy(prompt)
        refute_gentle_background(prompt)
        refute prompt =~ ~r/fuse/i
        assert prompt =~ ~r/instrumental/i
        assert prompt =~ ~r/volume/i
      end
    end

    test "a nonmusical Give supplies atmosphere rather than flattening composition" do
      for prompt <- briefs(["alpine meadow"]) do
        assert prompt =~ "alpine meadow"
        assert prompt =~ ~r/atmosphere only/i
        refute_gentle_background(prompt)
        refute prompt =~ ~r/fuse/i
      end
    end

    test "conflicting musical Gives invite a fusion rather than a common subdued style" do
      for prompt <- briefs(["Kiss Heavy Metal", "bossa nova"]) do
        assert prompt =~ "Kiss Heavy Metal"
        assert prompt =~ "bossa nova"
        assert prompt =~ ~r/fuse/i
        refute_gentle_background(prompt)
      end
    end

    test "the Vamp brief does not ask ElevenLabs for speech" do
      gives = ["Kiss Heavy Metal"]
      prompt = Music.vamp_prompt(gives)

      refute prompt =~ "conversational"
      refute prompt =~ "spoken conversation"
      assert String.starts_with?(prompt, Music.vamp_prefix(gives))
    end
  end

  describe "the Vamp brief fits ElevenLabs' 450 characters" do
    test "a table of four ordinary Gives is heard in full" do
      gives = ["the feeling of a Sunday night", "Vecna", "a can of worms", "grandma's kitchen"]
      prompt = Music.vamp_prompt(gives)

      assert String.length(prompt) <= 450
      for give <- gives, do: assert(prompt =~ give)
    end

    test "a table too long to fit keeps the direction and cuts the Gives at a word" do
      gives = for n <- 1..8, do: "an extraordinarily long and winding Give number #{n}"
      prompt = Music.vamp_prompt(gives)

      assert String.length(prompt) <= 450
      assert String.starts_with?(prompt, Music.vamp_prefix(gives))
      assert prompt =~ "an extraordinarily long and winding Give number 1"
      refute prompt =~ "number 8"
      refute String.ends_with?(prompt, " ")
      refute String.ends_with?(prompt, ",")
    end
  end

  defp briefs(gives), do: [Music.prompt(gives), Music.vamp_prompt(gives)]

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
