defmodule Thereish.Chronicle.Entry do
  @moduledoc """
  One closed Page as the Room hands it to the Chronicle: its Gives, Attempts,
  Bridges and Verdicts, the times Pacing recorded, the music Foley played and
  the Page's Assignment. Built when the Page closes and written once (ADR-0003).

  The Game builds it from its own state, and leaves nil what it cannot know:
  it keeps no clock and knows no Foley or experiment. Pacing stamps the times,
  the Room sets `music_meta` and `vamp_meta` from Occupancy and `assignment`
  from Pages, and Voice attaches
  each Verdict's `voice_meta`. Each sets its own fields by name.

  It carries exactly what the Chronicle writes, and nothing a screen shows.
  `page` is the Page's `Thereish.Chronicle.Document`. `author_meta` and each
  Verdict's `meta` stay opaque maps: they are stored as they come.
  `music_meta` and `vamp_meta` are the Page's `Thereish.Foley.Track` and
  `Thereish.Foley.Vamp`, and `masks` is each Seat's `Thereish.Mask` or `:dot`;
  the Page stores each through its own type.

  `bridges` on an Attempt is `%{seat_id, bridge}` per Seat that wrote one, in
  roster order. `nudges`, `calls` and `reactions` read the same way: the words
  spent on that Attempt, the band each Seat called during its Beat, and the one
  word each sent at its reveal — kept so the book reads as the table did, and
  never counted.
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
      nudges: [],
      calls: [],
      reactions: [],
      verdicts: []
    ]

    @type t :: %__MODULE__{
            number: pos_integer(),
            bookends: [String.t()],
            closeness: integer() | nil,
            melded?: boolean(),
            bridges: [%{seat_id: Ecto.UUID.t(), bridge: String.t()}],
            nudges: [%{seat_id: Ecto.UUID.t(), word: String.t()}],
            calls: [%{seat_id: Ecto.UUID.t(), band: atom()}],
            reactions: [%{seat_id: Ecto.UUID.t(), reaction: atom()}],
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
    :assignment,
    gives: [],
    masks: %{}
  ]

  @type t :: %__MODULE__{
          page: Thereish.Chronicle.Document.t(),
          gives: [Give.t()],
          masks: %{String.t() => Thereish.Mask.t() | :dot},
          author_meta: map() | nil,
          music_meta: Thereish.Foley.Track.t() | nil,
          vamp_meta: Thereish.Foley.Vamp.t() | nil,
          closed_because: :meld | :attempts_spent,
          melded?: boolean(),
          closeness: integer() | nil,
          attempts: [Attempt.t()],
          opened_at: DateTime.t() | nil,
          revealed_at: DateTime.t() | nil,
          assignment: Thereish.Experiments.Assignment.t() | nil
        }
end
