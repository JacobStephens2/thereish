defmodule Thereish.Chronicle.Entry do
  @moduledoc """
  One closed Page as the Room hands it to the Chronicle: its Gives, Attempts,
  Bridges and Verdicts, the times Pacing recorded, the music Foley played and
  the experiment arm. Built when the Page closes and written once (ADR-0003).

  The Game builds it from its own state, and leaves nil what it cannot know:
  it keeps no clock and knows no Foley or experiment. Pacing stamps the times,
  the Room sets `music_meta` and `vamp_meta` from Occupancy, and Voice attaches
  each Verdict's `voice_meta`. Each sets its own fields by name.

  It carries exactly what the Chronicle writes, and nothing a screen shows.
  `page`, `author_meta`, `music_meta`, `vamp_meta`, `masks` and each Verdict's
  `meta` stay opaque maps: they are stored as they come.

  `bridges` on an Attempt is `%{seat_id, bridge}` per Seat that wrote one, in
  roster order.
  """

  defmodule Give do
    @moduledoc "What one Seat gave the Author for the Page, and when it arrived."

    @enforce_keys [:seat_id, :text]
    defstruct [:seat_id, :text, :arrived_at]

    @type t :: %__MODULE__{
            seat_id: Ecto.UUID.t(),
            text: String.t(),
            arrived_at: DateTime.t() | nil
          }
  end

  defmodule Verdict do
    @moduledoc """
    The one Verdict the Assayer gave an Attempt's Bridges read together
    (ADR-0010). `seat_ids` and `bridges` run in the same order, so the row can
    be read without joining anything back to it.
    """

    @enforce_keys [:seat_ids, :bridges, :graded?]
    defstruct [
      :seat_ids,
      :bridges,
      :graded?,
      :closeness,
      :band,
      :reasoning,
      :quip,
      :furthest,
      :meta,
      :voice_meta,
      overruled?: false
    ]

    @type t :: %__MODULE__{
            seat_ids: [Ecto.UUID.t()],
            bridges: [String.t() | nil],
            graded?: boolean(),
            closeness: integer() | nil,
            band: atom() | nil,
            reasoning: String.t() | nil,
            quip: String.t() | nil,
            furthest: [String.t()] | nil,
            overruled?: boolean(),
            meta: map() | nil,
            voice_meta: map() | nil
          }
  end

  defmodule Attempt do
    @moduledoc "One Attempt at the Page, its Bridges, its Verdicts and when each step of it happened."

    @enforce_keys [:number, :bookends, :melded?]
    defstruct [
      :number,
      :bookends,
      :closeness,
      :melded?,
      :started_at,
      :assaying_started_at,
      :revealed_at,
      :advanced_at,
      bridges: [],
      verdicts: []
    ]

    @type t :: %__MODULE__{
            number: pos_integer(),
            bookends: [String.t()],
            closeness: integer() | nil,
            melded?: boolean(),
            bridges: [%{seat_id: Ecto.UUID.t(), bridge: String.t()}],
            verdicts: [Verdict.t()],
            started_at: DateTime.t() | nil,
            assaying_started_at: DateTime.t() | nil,
            revealed_at: DateTime.t() | nil,
            advanced_at: DateTime.t() | nil
          }
  end

  @enforce_keys [:page, :closed_because, :melded?, :attempts]
  defstruct [
    :page,
    :author_meta,
    :music_meta,
    :vamp_meta,
    :closed_because,
    :melded?,
    :closeness,
    :attempts,
    :opened_at,
    :revealed_at,
    :arm,
    gives: [],
    masks: %{}
  ]

  @type t :: %__MODULE__{
          page: map(),
          gives: [Give.t()],
          masks: map(),
          author_meta: map() | nil,
          music_meta: map() | nil,
          vamp_meta: map() | nil,
          closed_because: :meld | :attempts_spent,
          melded?: boolean(),
          closeness: integer() | nil,
          attempts: [Attempt.t()],
          opened_at: DateTime.t() | nil,
          revealed_at: DateTime.t() | nil,
          arm: atom() | nil
        }
end
