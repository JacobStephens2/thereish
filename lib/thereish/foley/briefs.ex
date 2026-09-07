defmodule Thereish.Foley.Briefs do
  @moduledoc """
  The fixed set of briefs for the sounds the game ships.

  Seventeen briefs:
  - The beat figure (2.5s rising, resolving on the downbeat)
  - Six stings: miss, adjacent, close, almost, meld, deep meld (under 2s; meld pair brighter, deep meld brightest)
  - Two endings: meld (an arrival), unmelded (a settle, not a sting)
  - Five house loops (Mureka instrumentals that sit under talk, each with a different mood)
  - Two victory cues: meld (an arrival that resolves), deep meld (brighter, a beat longer)
  - One commit tick: under half a second, soft click or wood tap
  """

  @briefs [
    %{
      id: :beat,
      key: "beat",
      name: "The Beat Figure",
      target_filename: "beat.mp3",
      kind: :effects,
      duration_seconds: 2.5,
      loop: false,
      prompt:
        "A 2.5-second rising musical figure that resolves cleanly on the downbeat. " <>
          "Building subtle anticipation, held breath, and then a decisive, satisfying resolution on the downbeat."
    },
    %{
      id: :sting_miss,
      key: "sting_miss",
      name: "Sting: Miss",
      target_filename: "sting-miss.mp3",
      kind: :effects,
      duration_seconds: 1.5,
      loop: false,
      prompt:
        "A short sound effect under 2 seconds. A miss: flat, deflating, gentle comical disappointment without being harsh or jarring."
    },
    %{
      id: :sting_adjacent,
      key: "sting_adjacent",
      name: "Sting: Adjacent",
      target_filename: "sting-adjacent.mp3",
      kind: :effects,
      duration_seconds: 1.5,
      loop: false,
      prompt:
        "A short sound effect under 2 seconds. Adjacent band: on the same block, across the street. A near miss, slightly curious, warm neutral tone."
    },
    %{
      id: :sting_close,
      key: "sting_close",
      name: "Sting: Close",
      target_filename: "sting-close.mp3",
      kind: :effects,
      duration_seconds: 1.5,
      loop: false,
      prompt:
        "A short sound effect under 2 seconds. Close band: passable, warm, encouraging mid-tone acoustic or synth chord."
    },
    %{
      id: :sting_almost,
      key: "sting_almost",
      name: "Sting: Almost",
      target_filename: "sting-almost.mp3",
      kind: :effects,
      duration_seconds: 1.5,
      loop: false,
      prompt:
        "A short sound effect under 2 seconds. Almost band: exciting, high anticipation, almost there, bright and vibrant."
    },
    %{
      id: :sting_meld,
      key: "sting_meld",
      name: "Sting: Meld",
      target_filename: "sting-meld.mp3",
      kind: :effects,
      duration_seconds: 1.8,
      loop: false,
      prompt:
        "A short sound effect under 2 seconds. Meld: brighter than the other stings, sparkling, synchronized harmony, two minds connecting."
    },
    %{
      id: :sting_deep_meld,
      key: "sting_deep_meld",
      name: "Sting: Deep Meld",
      target_filename: "sting-deep-meld.mp3",
      kind: :effects,
      duration_seconds: 2.0,
      loop: false,
      prompt:
        "A short sound effect under 2 seconds. Deep meld: the brightest sting of all, radiant chime, triumph, deep harmonic resonance, perfect unity."
    },
    %{
      id: :ending_meld,
      key: "ending_meld",
      name: "Ending: Meld",
      target_filename: "ending-meld.mp3",
      kind: :effects,
      duration_seconds: 3.0,
      loop: false,
      prompt:
        "An ending sound effect: an arrival, not a sting. Warm, celebratory closure, a journey reached, triumphant and satisfying."
    },
    %{
      id: :ending_unmelded,
      key: "ending_unmelded",
      name: "Ending: Unmelded",
      target_filename: "ending-unmelded.mp3",
      kind: :effects,
      duration_seconds: 3.0,
      loop: false,
      prompt:
        "An ending sound effect: a settle, not a sting. Gentle, peaceful closure for an unmelded page, an exhale, thoughtful and comforting."
    },
    %{
      id: :house_loop,
      key: "house_loop",
      name: "House Loop",
      target_filename: "house-loop.mp3",
      kind: :music,
      loop: true,
      prompt:
        "An understated, warm instrumental acoustic loop that sits gently under living room conversation. Unhurried acoustic guitars, subtle percussion, ambient warmth."
    },
    %{
      id: :house_loop_2,
      key: "house_loop_2",
      name: "House Loop 2",
      target_filename: "house-loop-2.mp3",
      kind: :music,
      loop: true,
      prompt:
        "An understated, warm instrumental acoustic loop that sits gently under living room conversation. A reflective, gentle mood with soft fingerpicked acoustic guitar and warm mellow tones."
    },
    %{
      id: :house_loop_3,
      key: "house_loop_3",
      name: "House Loop 3",
      target_filename: "house-loop-3.mp3",
      kind: :music,
      loop: true,
      prompt:
        "An understated, warm instrumental acoustic loop that sits gently under living room conversation. A light, breezy, sunlit mood with delicate acoustic strumming and subtle, airy percussion."
    },
    %{
      id: :house_loop_4,
      key: "house_loop_4",
      name: "House Loop 4",
      target_filename: "house-loop-4.mp3",
      kind: :music,
      loop: true,
      prompt:
        "An understated, warm instrumental acoustic loop that sits gently under living room conversation. A quiet, cozy late-evening mood with soft nylon guitar, gentle ambient texture, and a relaxed cadence."
    },
    %{
      id: :house_loop_5,
      key: "house_loop_5",
      name: "House Loop 5",
      target_filename: "house-loop-5.mp3",
      kind: :music,
      loop: true,
      prompt:
        "An understated, warm instrumental acoustic loop that sits gently under living room conversation. A spacious, atmospheric mood with open acoustic chords, lingering resonance, and subtle warmth."
    },
    %{
      id: :victory_meld,
      key: "victory_meld",
      name: "Victory: Meld",
      target_filename: "victory-meld.mp3",
      kind: :effects,
      duration_seconds: 9.5,
      loop: false,
      prompt:
        "A celebratory victory cue between 8 and 12 seconds: an arrival that resolves. Warm, triumphant closure with radiant acoustic chords, synchronized harmony, celebrating a meld reached."
    },
    %{
      id: :victory_deep_meld,
      key: "victory_deep_meld",
      name: "Victory: Deep Meld",
      target_filename: "victory-deep-meld.mp3",
      kind: :effects,
      duration_seconds: 11.5,
      loop: false,
      prompt:
        "A celebratory victory cue between 8 and 12 seconds: the same arrival idea brighter and a beat longer. Sparkling triumphant chime, profound harmonic resonance, celebrating a deep meld."
    },
    %{
      id: :commit_tick,
      key: "commit_tick",
      name: "Commit Tick",
      target_filename: "commit-tick.mp3",
      kind: :effects,
      duration_seconds: 0.5,
      loop: false,
      prompt:
        "A very short sound effect under half a second. A soft click or organic wood tap, tactile and crisp, non-tonal enough to never clash with music."
    }
  ]

  @spec all() :: [map()]
  def all, do: @briefs

  @spec get(atom() | String.t()) :: map() | nil
  def get(key) do
    str_key = to_string(key)

    Enum.find(
      @briefs,
      &(to_string(&1.key) == str_key or to_string(&1.id) == str_key or
          &1.target_filename == str_key)
    )
  end
end
