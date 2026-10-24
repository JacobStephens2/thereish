defmodule Thereish.Steward.Fake do
  @moduledoc """
  The test adapter for the Author, Assayer, Scribe, Foley and Limner.

  It supplies configurable writing and grading responses plus fixtures for
  naming, music, voice, effects and images, without making provider calls.
  Tests can request delays and failure modes through the same Steward
  interface used by live play.

  The fake Assayer returns the same grade for the same Bridges, every time,
  at whatever speed the caller asked for. It grades on the letters two Bridges
  share from the front, which is not a measure of meaning and is not trying to
  be. It is a **dial**: a test that
  wants a Meld writes "cairn" and "cairo", one that wants a miss writes "cairn"
  and "beacon", and neither has to know anything about a model. Every test that
  is not a hand-run smoke test grades against this, so the numbers a test asserts
  on are the ones it chose.

  At more than two Bridges it stays a dial. The Closeness is the mean of that
  same shared-prefix grade over every pair, and the two words it names as
  furthest apart are the pair that scored lowest, ties going to whichever came
  first in roster order. At exactly two Bridges there is one pair, so the mean is
  that pair's grade and the furthest two are the only two — which is what makes
  every grade the couch's tests were written against still the grade they get
  (ADR-0010). Bookends of two or more are accepted and ignored: this Assayer
  grades the Bridges, not the table they were written against.

  Like any adapter, it grades the one ordering of the Bridges it is handed.
  The Steward asks it for both orderings and reconciles them into the Verdict,
  so a Room played on this Assayer is graded by the same rule as one played on
  a model. The two orderings grade the same here, because shared prefixes do
  not care which word came first; only the furthest pair's tie-break and the
  order the reasoning names the two words in follow the ordering.

  Two knobs, both configuration, both for the tests that need the Room to be
  waiting on something:

      config :thereish, :steward, fake: [delay_ms: 0, mode: :grade]

  `delay_ms` is how long grading one ordering takes; the Steward asks for both
  at once, so it is how long a verdict takes too. `mode: :unavailable` is an Assayer
  that says it cannot answer, and `mode: :raise` is one that falls over without
  saying anything — the two shapes a failed grade comes in, both of which the
  game answers the same way.

  `quip/1` is the fresh Quip the Steward asks for on a Precedent hit. It is the
  Quip this Assayer's own grade writes for those Bridges, and it answers to the
  same two dials, so a test that wants the Steward to fall back on the cached
  Quip sets `mode: :unavailable` or a `delay_ms` past the Quip's timeout.

  ## Author and Scribe controls

  The Author and the Scribe have the same dials under the same names —
  `author_mode`, `author_delay_ms`, `recap_mode`, `recap_delay_ms` — and the
  Scribe takes a `recap` and a `recap_callback` for a test that wants particular
  prose. Left alone, the fake Scribe writes the one true sentence about a Page
  out of the Bridges in it, and reaches back for a callback only when the digest
  it was handed has something in it, which is the same thing that decides it for
  the real one.
  """
  @behaviour Thereish.Steward

  @impl true
  def assay(%{bookends: bookends} = request, ordering)
      when is_list(bookends) and length(bookends) >= 2 and length(ordering) >= 2 do
    case config_get(:assay_capture, nil) do
      pid when is_pid(pid) -> send(pid, {:assay, request, ordering})
      _ -> :ok
    end

    delay_ms() |> Process.sleep()

    case mode() do
      :grade -> {:ok, grade(ordering)}
      :unavailable -> {:error, :no_verdict}
      :raise -> raise "this Assayer is having a moment"
    end
  end

  # The Quip its own grade writes for these Bridges, so a Precedent hit reads
  # the same on every screen as the grade that set it. It answers to the
  # Assayer's dials, because a fresh Quip is the Assayer's to write.
  @impl true
  def quip(%{bridges: bridges}) when length(bridges) >= 2 do
    delay_ms() |> Process.sleep()

    case mode() do
      :grade -> {:ok, %{quip: grade(bridges).quip, meta: %{cost_usd: 0.0}}}
      :unavailable -> {:error, :no_quip}
      :raise -> raise "this Assayer is having a moment"
    end
  end

  @bookend_pool ~w(lantern harbour summit ember grove spire ridge hearth)
  @bookend_laps ~w(old new far near high low deep wide)

  @impl true
  def author(request, opts \\ []) do
    delay = author_delay_ms()
    if delay > 0, do: Process.sleep(delay)

    case author_mode() do
      :ok ->
        count = Thereish.Steward.Author.requested_count(request)

        bookends =
          Keyword.get(opts, :bookends) ||
            config_get(:author_bookends, pool_bookends(count))

        why =
          Keyword.get(opts, :why) ||
            config_get(
              :author_why,
              "A light to see by stands opposite a shelter by the water."
            )

        job = Keyword.get(opts, :job, :flash)
        arm = Keyword.get(opts, :arm, job)

        {:ok,
         %{
           bookends: bookends,
           from: author_from(request, count),
           why: why,
           meta: %{
             model: "fake-author",
             arm: arm,
             prompt_version: Thereish.Steward.Author.version(),
             cost_usd: 0.0,
             latency_ms: delay,
             attempts: 1,
             why: why,
             count: count
           }
         }}

      :refused ->
        {:error, :refused}

      :unavailable ->
        {:error, :unavailable}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Author is having a moment"
    end
  end

  # N Bookends for whatever N a Full table asks for, all of them distinct: the
  # pool first, then the pool again under a two-word phrase. A Page whose
  # Bookends repeat a word is not a Page any width of table would be handed, so
  # the fake never hands one out either.
  defp pool_bookends(count) do
    size = length(@bookend_pool)

    for i <- 0..(count - 1)//1 do
      word = Enum.at(@bookend_pool, rem(i, size))

      case div(i, size) do
        0 -> word
        lap -> Enum.at(@bookend_laps, rem(lap - 1, length(@bookend_laps))) <> " " <> word
      end
    end
  end

  # The setting each Bookend was drawn from, in the order the Bookends came. The
  # Gives are walked round and round until every Bookend has one, so a Page that
  # asks for more Bookends than it has Gives still names every setting at least
  # once — which is what the Author's own gate asks for.
  defp author_from(request, count) do
    gives =
      cond do
        is_map(request) and is_list(request[:gives]) -> request[:gives]
        is_map(request) and is_list(request["gives"]) -> request["gives"]
        is_list(request) -> request
        true -> []
      end

    case gives do
      [] ->
        []

      gives ->
        gives
        |> Stream.cycle()
        |> Enum.take(count)
        |> Enum.map(&Thereish.Steward.Author.give_name/1)
    end
  end

  @impl true
  def recap(page, digest) do
    delay = config_get(:recap_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:recap_mode, :ok) do
      :ok ->
        {:ok,
         %{
           recap: config_get(:recap, nil) || written(page),
           callback: config_get(:recap_callback, nil) || remembered(digest),
           meta: %{
             model: "fake-scribe",
             prompt_version: "fake-recap-1",
             cost_usd: 0.0,
             latency_ms: delay,
             attempts: 1
           }
         }}

      :unavailable ->
        {:error, :no_recap}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Scribe is having a moment"
    end
  end

  @impl true
  def forge(_brief, opts \\ []) do
    delay = config_get(:foley_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:forge_mode, :ok) do
      :ok ->
        n = Keyword.get(opts, :n, 4)

        candidates =
          for i <- 1..n do
            %{
              bytes: <<255, 251, 144, 100, i::8, 0, 0, 0, 0, 0, 0, 0>>,
              meta: %{
                model: "fake",
                cost_usd: 0.0,
                latency_ms: delay
              }
            }
          end

        {:ok, candidates}

      :unavailable ->
        {:error, :no_foley}

      :raise ->
        raise "this Foley is having a moment"
    end
  end

  @impl true
  def rank(candidates, _brief) do
    delay = config_get(:foley_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:rank_mode, :ok) do
      :ok ->
        ordering =
          Enum.map(Enum.with_index(candidates, 1), fn {_clip, idx} ->
            %{
              index: idx,
              reason: "Candidate #{idx} fits the brief.",
              meta: %{
                model: "fake-ear",
                cost_usd: 0.0,
                latency_ms: delay
              }
            }
          end)

        {:ok, ordering}

      :unavailable ->
        {:error, :no_ear}

      :raise ->
        raise "this Ear is having a moment"
    end
  end

  @impl true
  def name_room([], _taken_codes), do: {:error, :no_history}

  def name_room(_digests, _taken_codes) do
    delay = config_get(:name_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:name_mode, :ok) do
      :ok ->
        case config_get(:name_word, "cane") do
          nil ->
            {:error, :no_name}

          word ->
            quip = config_get(:name_quip, "A room from the old days.")
            {:ok, %{word: word, quip: quip}}
        end

      :unavailable ->
        {:error, :no_name}

      :raise ->
        raise "this Scribe is having a moment"
    end
  end

  @impl true
  def quip_code(_code) do
    delay = config_get(:quip_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:quip_mode, :ok) do
      :ok ->
        case config_get(:quip_text, "A fine room.") do
          nil -> {:error, :no_quip}
          quip -> {:ok, quip}
        end

      :unavailable ->
        {:error, :no_quip}

      :raise ->
        raise "this Scribe is having a moment"
    end
  end

  @mp3_fixture <<255, 251, 144, 100>> <> :binary.copy(<<0>>, 413)

  @doc "Fixture MP3 bytes used by the Fake voice and test fixtures."
  def mp3_fixture, do: @mp3_fixture

  @impl true
  def speak(line, opts \\ []) do
    delay = voice_delay_ms()
    if delay > 0, do: Process.sleep(delay)

    case voice_mode() do
      :ok ->
        if recipient = config_get(:voice_recipient, nil) do
          send(recipient, {:fake_speak, line})
        end

        {:ok,
         %{
           audio: mp3_fixture(),
           format: :mp3,
           meta: %{
             provider: "fake",
             voice_id: Keyword.get(opts, :voice_id, "fake-voice"),
             cost_usd: 0.0,
             latency_ms: delay,
             characters: String.length(line)
           }
         }}

      :unavailable ->
        {:error, :voice_unavailable}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Voice is having a moment"
    end
  end

  @impl true
  def score(gives, opts \\ []) do
    delay = music_delay_ms()
    if delay > 0, do: Process.sleep(delay)

    case music_mode() do
      :ok ->
        key = fake_music_key(gives)

        path =
          Keyword.get(opts, :path) || config_get(:music_path, "/media/tracks/fake-#{key}.mp3")

        {:ok,
         %{
           path: path,
           duration: config_get(:music_duration, 120),
           format: :mp3,
           meta: %{
             provider: "fake",
             model: "fake-music",
             cost_usd: 0.04,
             latency_ms: delay
           }
         }}

      :unavailable ->
        {:error, :music_unavailable}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Foley is having a moment"
    end
  end

  @impl true
  def vamp(gives, opts \\ []) do
    delay = config_get(:vamp_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:vamp_mode, :ok) do
      :ok ->
        key = fake_music_key(gives)

        path =
          Keyword.get(opts, :path) || config_get(:vamp_path, "/media/vamps/fake-#{key}.mp3")

        {:ok,
         %{
           path: path,
           duration: config_get(:vamp_duration, 30),
           format: :mp3,
           loop: true,
           meta: %{
             provider: "fake",
             model: "fake-vamp",
             cost_usd: 0.0,
             latency_ms: delay,
             loop: true
           }
         }}

      :unavailable ->
        {:error, :vamp_unavailable}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Foley is having a moment"
    end
  end

  defp fake_music_key(gives) do
    gives
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.sort()
    |> Enum.join("-")
  end

  @impl true
  def draw(give, colour, opts \\ []) do
    if recipient = config_get(:draw_capture, nil) do
      send(recipient, {:draw, give, colour, opts})
    end

    delay = draw_delay_ms()
    if delay > 0, do: Process.sleep(delay)

    case draw_mode() do
      :ok ->
        size = Keyword.get(opts, :size, 64)
        bytes = Thereish.Steward.Limner.png(colour, size)

        {:ok,
         %{
           bytes: bytes,
           format: :png,
           meta: %{
             provider: "fake",
             model: "fake-limner",
             cost_usd: 0.0,
             latency_ms: delay,
             give: Thereish.Steward.Author.give_text(give),
             colour: colour
           }
         }}

      :refused ->
        {:error, :refused}

      :unavailable ->
        {:error, :draw_unavailable}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Limner is having a moment"
    end
  end

  @impl true
  def title_track(gives, opts \\ []) do
    delay = title_delay_ms()
    if delay > 0, do: Process.sleep(delay)

    case title_mode() do
      :ok ->
        title =
          Keyword.get(opts, :title) ||
            config_get(:title_text, nil) ||
            Thereish.Steward.Title.fallback(gives)

        {:ok,
         %{
           title: title,
           meta: %{
             provider: "fake",
             model: "fake-scribe",
             cost_usd: 0.0001,
             latency_ms: delay
           }
         }}

      :unavailable ->
        {:error, :title_unavailable}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Scribe is having a moment"
    end
  end

  # The Scribe with no model behind it writes the one true sentence about a
  # Page: who wrote what, first and last. It is a dial like the grade is — a
  # test that wants a recap naming a word writes that word as a Bridge — and it
  # is deliberately prose the real Vale gate would pass, so that no test is ever
  # asserting on a paragraph the couch would never be shown.
  defp written(page) do
    first = List.first(page.attempts)
    last = List.last(page.attempts)

    opening = Enum.map_join(first.bridges, ", ", &~s(#{&1.seat_name} wrote "#{&1.bridge}"))
    closing = Enum.map_join(last.bridges, " and ", &~s("#{&1.bridge}"))

    ending = if page.melded, do: "They met at", else: "They ended on"

    "On the first attempt, #{opening}. #{ending} #{closing}."
  end

  # A callback needs a Chronicle to reach back into, and a Room playing its
  # first Page has none. The fake tells the two apart the same way the real
  # Scribe is asked to: by whether the digest has anything in it.
  defp remembered("Nothing yet" <> _rest), do: nil
  defp remembered(_digest), do: "They have been here before."

  defp author_delay_ms, do: config_get(:author_delay_ms, 0)
  defp author_mode, do: config_get(:author_mode, :ok)
  defp voice_delay_ms, do: config_get(:voice_delay_ms, 0)
  defp voice_mode, do: config_get(:voice_mode, :ok)
  defp music_delay_ms, do: config_get(:music_delay_ms, 0)
  defp music_mode, do: config_get(:music_mode, :ok)
  defp title_delay_ms, do: config_get(:title_delay_ms, 0)
  defp title_mode, do: config_get(:title_mode, :ok)
  defp draw_delay_ms, do: config_get(:draw_delay_ms, 0)
  defp draw_mode, do: config_get(:draw_mode, :ok)

  defp config_get(key, default) do
    :thereish
    |> Application.get_env(:steward, [])
    |> Keyword.get(:fake, [])
    |> Keyword.get(key, default)
  end

  defp grade(bridges) do
    graded = for pair <- every_pair(bridges), do: {pair, pair_closeness(pair)}
    closeness = graded |> Enum.map(&elem(&1, 1)) |> mean()

    # The pair the arithmetic liked least, which is this Assayer's whole idea of
    # two words having landed far apart. `min_by` keeps the first of a tie, and
    # the pairs come out in roster order, so a table that ties gets the same
    # answer every time it plays.
    {[left, right], _lowest} = Enum.min_by(graded, &elem(&1, 1))
    shared = shared_prefix(normalize_bridge(left), normalize_bridge(right))

    %{
      closeness: closeness,
      # The reasoning and the quip both name the furthest two, which at two
      # Bridges is both of them: every sentence this Assayer has ever written
      # about a pair is the sentence it still writes.
      reasoning:
        "\"#{left}\" and \"#{right}\" share #{shared} letters from the front. " <>
          "That is all this Assayer knows how to look at.",
      # Named after the players' actual Bridges, like the live one's, so that
      # every screen the quip is drawn on is exercised by a test that never
      # calls anybody (ADR-0005).
      quip: "\"#{left}\" and \"#{right}\" walk into a bar. The bar has no opinion.",
      furthest: [left, right],
      # Which model answered and what it cost, answered honestly by the one that
      # has no model behind it and costs nothing to run.
      model: "fake",
      cost_usd: 0.0
    }
  end

  # Every unordered pair, in roster order, so that the tie-break is the order the
  # Seats are sitting in rather than the order a map happened to iterate.
  defp every_pair(bridges) do
    bridge_strings = Enum.map(bridges, &bridge_text/1)

    for {left, i} <- Enum.with_index(bridge_strings),
        {right, j} <- Enum.with_index(bridge_strings),
        i < j,
        do: [left, right]
  end

  defp bridge_text(item), do: Thereish.Steward.Legality.bridge_text(item)

  defp normalize_bridge(str) do
    str
    |> bridge_text()
    |> Thereish.Steward.Legality.normalize_bridge()
  end

  @doc "Grades one pair of bridges based on shared prefix."
  def pair_closeness([left, right]) do
    l_norm = normalize_bridge(left)
    r_norm = normalize_bridge(right)
    total_len = String.length(l_norm) + String.length(r_norm)

    if total_len == 0 do
      0
    else
      round(200 * shared_prefix(l_norm, r_norm) / total_len)
    end
  end

  # Rounded once at the end. At two Bridges there is one pair and rounding an
  # already-rounded number changes nothing, which is the point.
  defp mean(closenesses), do: round(Enum.sum(closenesses) / length(closenesses))

  defp shared_prefix(left, right) do
    left
    |> String.graphemes()
    |> Enum.zip(String.graphemes(right))
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> length()
  end

  defp delay_ms, do: config(:delay_ms)

  defp mode, do: config(:mode)

  defp config(key) do
    :thereish
    |> Application.fetch_env!(:steward)
    |> Keyword.fetch!(:fake)
    |> Keyword.fetch!(key)
  end
end
