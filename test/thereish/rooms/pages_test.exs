defmodule Thereish.Rooms.PagesTest do
  @moduledoc """
  Closed Entry retention and which Chronicle Page each late result belongs
  to, driven through the interface and asserted on submitted Entries and writes.

  A write here is any term: the module never looks inside one.
  """
  use ExUnit.Case, async: true

  alias Thereish.Experiments.Assignment
  alias Thereish.Rooms.Pages

  import Thereish.EntryFixtures

  @flash %Assignment{id: "assignment-1", experiment_id: "author_model", arm: :flash}
  @astra %Assignment{id: "assignment-2", experiment_id: "author_model", arm: :astra}

  defp opened(assignment \\ @flash) do
    page_ref = make_ref()
    {Pages.page_opened(Pages.new(), page_ref, assignment), page_ref}
  end

  defp closed_entry(numbers \\ [1]) do
    entry(attempts: Enum.map(numbers, &%{number: &1, verdicts: [%{}]}))
  end

  defp close(pages) do
    {pages, [{:commit_chronicle, _entry}]} = Pages.page_closed(pages, closed_entry())
    pages
  end

  defp pending(pages, attempt \\ 1) do
    {pages, []} = Pages.verdict_pending(pages, attempt)
    pages
  end

  test "a closed Entry without pending Verdict speech is submitted immediately" do
    closed = entry()
    assert {_pages, [{:commit_chronicle, ^closed}]} = Pages.page_closed(Pages.new(), closed)
  end

  test "pending Verdict speech holds the Entry until its metadata arrives" do
    {pages, []} = Pages.verdict_pending(Pages.new(), 1)
    {pages, []} = Pages.page_closed(pages, entry(attempts: [%{verdicts: [%{}]}]))
    meta = %{"provider" => "fake", "voice" => "v1"}

    assert {pages, [{:commit_chronicle, committed}]} = Pages.verdict_spoken(pages, 1, meta)
    assert [%{verdicts: [%{voice_meta: ^meta}]}] = committed.attempts
    assert {_pages, []} = Pages.verdict_spoken(pages, 1, meta)
  end

  test "a write for a written Page lands now" do
    {pages, page_ref} = opened()
    {pages, []} = Pages.written(close(pages), "page-1")

    assert {_pages, [{:write, "page-1", :track}]} = Pages.write(pages, page_ref, :track)
  end

  test "the giving ref names the same Page as the Page refs asked under it" do
    {pages, _page_ref} = opened()
    giving = Pages.giving(pages)
    {pages, []} = Pages.written(close(pages), "page-1")

    assert {_pages, [{:write, "page-1", :mask}]} = Pages.write(pages, giving, :mask)
  end

  test "writes for a closed Page are held until it is written, then released in order" do
    {pages, page_ref} = opened()
    giving = Pages.giving(pages)
    pages = close(pages)

    {pages, []} = Pages.write(pages, giving, :mask)
    {pages, []} = Pages.write(pages, page_ref, :track)
    {pages, []} = Pages.write(pages, giving, :tap)

    assert {pages, writes} = Pages.written(pages, "page-1")

    assert writes == [
             {:write, "page-1", :mask},
             {:write, "page-1", :track},
             {:write, "page-1", :tap}
           ]

    assert {_pages, [{:write, "page-1", :vamp}]} = Pages.write(pages, page_ref, :vamp)
  end

  test "a write for the Page in play before it closes is dropped: the closing entry carries it" do
    {pages, page_ref} = opened()
    {pages, []} = Pages.write(pages, Pages.giving(pages), :mask)
    {pages, []} = Pages.write(pages, page_ref, :track)
    pages = close(pages)

    assert {_pages, []} = Pages.written(pages, "page-1")
  end

  test "a reset giving drops anything that comes later for it" do
    {pages, page_ref} = opened()
    old_giving = Pages.giving(pages)

    pages = Pages.gives_reset(pages)
    refute Pages.giving(pages) == old_giving

    {pages, []} = Pages.write(pages, page_ref, :late_track)
    {pages, []} = Pages.write(pages, old_giving, :late_mask)
    pages = Pages.page_opened(pages, make_ref(), @flash)

    assert {_pages, []} = Pages.written(close(pages), "page-1")
  end

  test "refs from an Author retry resolve to the same Page" do
    {pages, first_ref} = opened()
    retry_ref = make_ref()
    pages = pages |> Pages.page_opened(retry_ref, @flash) |> close()
    {pages, []} = Pages.write(pages, first_ref, :vamp)

    assert {pages, [{:write, "page-1", :vamp}]} = Pages.written(pages, "page-1")
    assert {pages, [{:write, "page-1", :a}]} = Pages.write(pages, first_ref, :a)
    assert {_pages, [{:write, "page-1", :b}]} = Pages.write(pages, retry_ref, :b)
  end

  test "turning the Page forgets the writes held for a Page that was never written" do
    {pages, page_ref} = opened()
    pages = close(pages)
    {pages, []} = Pages.write(pages, page_ref, :track)

    {pages, []} = Pages.page_turned(pages)
    {pages, []} = Pages.write(pages, page_ref, :late_track)
    pages = pages |> Pages.page_opened(make_ref(), @astra) |> close()

    assert {_pages, []} = Pages.written(pages, "page-2")
  end

  test "a written Page keeps taking writes after the Page has turned" do
    {pages, page_ref} = opened()
    giving = Pages.giving(pages)
    {pages, []} = Pages.written(close(pages), "page-1")

    {pages, []} = Pages.page_turned(pages)
    pages = Pages.page_opened(pages, make_ref(), @astra)
    {pages, []} = Pages.written(close(pages), "page-2")

    assert {pages, [{:write, "page-1", :mask}]} = Pages.write(pages, giving, :mask)
    assert {_pages, [{:write, "page-1", :track}]} = Pages.write(pages, page_ref, :track)
  end

  test "a ref the Room never opened is dropped" do
    {pages, _page_ref} = opened()
    pages = close(pages)

    assert {_pages, []} = Pages.write(pages, make_ref(), :stray)
  end

  test "the Assignment of the Page in play survives new Gives but not a turned Page" do
    assert Pages.assignment(Pages.new()) == nil

    {pages, _page_ref} = opened(@astra)
    assert Pages.assignment(pages) == @astra

    pages = Pages.gives_reset(pages)
    assert Pages.assignment(pages) == @astra

    {pages, []} = Pages.page_turned(pages)
    assert Pages.assignment(pages) == nil
  end

  test "failed speech metadata is included in the initial insertion" do
    failure = %{"provider" => "fake", "cost_usd" => 0.0, "failure" => "unavailable"}
    {pages, []} = Pages.page_closed(pending(Pages.new()), closed_entry())

    assert {_pages, [{:commit_chronicle, committed}]} = Pages.verdict_spoken(pages, 1, failure)
    assert [%{verdicts: [%{voice_meta: ^failure}]}] = committed.attempts
  end

  test "completed metadata attaches to each matching Attempt and Verdict before closure" do
    first = %{"voice" => "v1"}
    second = %{"voice" => "v2"}
    {pages, []} = Pages.verdict_spoken(pending(Pages.new()), 1, first)
    {pages, []} = Pages.verdict_spoken(pending(pages, 2), 2, second)

    assert {_pages, [{:commit_chronicle, committed}]} =
             Pages.page_closed(pages, closed_entry([1, 2, 3]))

    assert [
             %{verdicts: [%{voice_meta: ^first}]},
             %{verdicts: [%{voice_meta: ^second}]},
             %{verdicts: [%{voice_meta: nil}]}
           ] = committed.attempts
  end

  test "only the latest pending Verdict delays the Entry and releases it" do
    pages = Pages.new() |> pending(1) |> pending(2)
    {pages, []} = Pages.page_closed(pages, closed_entry([1, 2]))
    {pages, []} = Pages.verdict_spoken(pages, 1, %{"voice" => "earlier"})

    assert {_pages, [{:commit_chronicle, committed}]} =
             Pages.verdict_spoken(pages, 2, %{"voice" => "closing"})

    assert [
             %{verdicts: [%{voice_meta: %{"voice" => "earlier"}}]},
             %{verdicts: [%{voice_meta: %{"voice" => "closing"}}]}
           ] = committed.attempts
  end

  test "an earlier completion after the latest one still attaches before closure" do
    pages = Pages.new() |> pending(1) |> pending(2)
    {pages, []} = Pages.verdict_spoken(pages, 2, %{"voice" => "latest"})
    {pages, []} = Pages.verdict_spoken(pages, 1, %{"failure" => "earlier"})
    {_pages, [{:commit_chronicle, committed}]} = Pages.page_closed(pages, closed_entry([1, 2]))

    assert [
             %{verdicts: [%{voice_meta: %{"failure" => "earlier"}}]},
             %{verdicts: [%{voice_meta: %{"voice" => "latest"}}]}
           ] = committed.attempts
  end

  test "earlier pending speech and a pending Attempt outside the Entry add no wait" do
    pages = Pages.new() |> pending(1) |> pending(2)
    {pages, []} = Pages.verdict_spoken(pages, 2, %{"voice" => "closing"})
    assert {_pages, [{:commit_chronicle, _}]} = Pages.page_closed(pages, closed_entry([1, 2]))

    assert {_pages, [{:commit_chronicle, _}]} =
             Pages.page_closed(pending(Pages.new(), 3), closed_entry([1, 2]))
  end

  test "a turn flushes once, binds the submitted refs and preserves the next Page" do
    {pages, first_ref} = opened()
    giving = Pages.giving(pages)
    retry_ref = make_ref()
    pages = pages |> Pages.page_opened(retry_ref, @flash) |> pending(1)
    {pages, []} = Pages.verdict_spoken(pages, 1, %{"voice" => "earlier"})
    {pages, []} = Pages.page_closed(pending(pages, 2), closed_entry([1, 2]))
    {pages, []} = Pages.write(pages, giving, :mask)
    {pages, []} = Pages.write(pages, first_ref, :vamp)
    {pages, []} = Pages.write(pages, retry_ref, :track)
    {pages, []} = Pages.write(pages, giving, :tap)

    assert {pages, [{:commit_chronicle, committed}]} = Pages.page_turned(pages)

    assert [
             %{verdicts: [%{voice_meta: %{"voice" => "earlier"}}]},
             %{verdicts: [%{voice_meta: nil}]}
           ] = committed.attempts

    refute Pages.giving(pages) == giving
    assert Pages.assignment(pages) == nil

    next_giving = Pages.giving(pages)
    next_ref = make_ref()
    pages = Pages.page_opened(pages, next_ref, @astra)
    assert {pages, writes} = Pages.written(pages, "page-1")
    assert writes == Enum.map([:mask, :vamp, :track, :tap], &{:write, "page-1", &1})
    assert Pages.giving(pages) == next_giving
    assert Pages.assignment(pages) == @astra
    assert {pages, []} = Pages.verdict_spoken(pages, 2, %{"voice" => "late"})
    assert {pages, [{:write, "page-1", :late_mask}]} = Pages.write(pages, giving, :late_mask)
    assert {pages, [{:write, "page-1", :late_vamp}]} = Pages.write(pages, first_ref, :late_vamp)
    assert {pages, [{:write, "page-1", :late_track}]} = Pages.write(pages, retry_ref, :late_track)
    assert {pages, []} = Pages.write(pages, next_ref, :new_track)
    assert {_pages, []} = Pages.page_turned(pages)
  end

  test "a later close retires an unacknowledged turn without releasing its FIFO" do
    {pages, old_ref} = opened()
    {pages, []} = Pages.page_closed(pending(pages), closed_entry())
    {pages, []} = Pages.write(pages, old_ref, :old_track)
    {pages, [{:commit_chronicle, _}]} = Pages.page_turned(pages)
    pages = Pages.page_opened(pages, make_ref(), @astra)
    pages = close(pages)
    {pages, []} = Pages.written(pages, "page-2")
    assert {_pages, []} = Pages.write(pages, old_ref, :late_track)
  end

  test "reset and turn forget speech metadata and ignore abandoned completions" do
    for reset <- [&Pages.gives_reset/1, fn pages -> elem(Pages.page_turned(pages), 0) end] do
      {pages, []} = Pages.verdict_spoken(pending(Pages.new()), 1, %{"voice" => "old"})
      pages = pages |> pending(2) |> reset.()
      {pages, []} = Pages.verdict_spoken(pages, 2, %{"voice" => "late"})
      {_pages, [{:commit_chronicle, committed}]} = Pages.page_closed(pages, closed_entry([1, 2]))

      assert Enum.all?(committed.attempts, fn attempt ->
               Enum.all?(attempt.verdicts, &is_nil(&1.voice_meta))
             end)
    end
  end
end
