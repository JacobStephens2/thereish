defmodule Thereish.Rooms.PagesTest do
  @moduledoc """
  Which Chronicle Page each late result belongs to, driven call by call
  through the module's interface and asserted on the writes it asks for.

  A write here is any term: the module never looks inside one.
  """
  use ExUnit.Case, async: true

  alias Thereish.Experiments.Assignment
  alias Thereish.Rooms.Pages

  @flash %Assignment{id: "assignment-1", experiment_id: "author_model", arm: :flash}
  @astra %Assignment{id: "assignment-2", experiment_id: "author_model", arm: :astra}

  defp opened(assignment \\ @flash) do
    page_ref = make_ref()
    {Pages.page_opened(Pages.new(), page_ref, assignment), page_ref}
  end

  test "a write for a written Page lands now" do
    {pages, page_ref} = opened()
    {pages, []} = Pages.written(pages, "page-1")

    assert {_pages, [{:write, "page-1", :track}]} = Pages.write(pages, page_ref, :track)
  end

  test "the giving ref names the same Page as the Page refs asked under it" do
    {pages, _page_ref} = opened()
    giving = Pages.giving(pages)
    {pages, []} = Pages.written(pages, "page-1")

    assert {_pages, [{:write, "page-1", :mask}]} = Pages.write(pages, giving, :mask)
  end

  test "writes for a closed Page are held until it is written, then released in order" do
    {pages, page_ref} = opened()
    giving = Pages.giving(pages)
    pages = Pages.page_closed(pages)

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
    pages = Pages.page_closed(pages)

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

    assert {_pages, []} = Pages.written(pages, "page-1")
  end

  test "refs from an Author retry resolve to the same Page" do
    {pages, first_ref} = opened()
    retry_ref = make_ref()
    pages = pages |> Pages.page_opened(retry_ref, @flash) |> Pages.page_closed()
    {pages, []} = Pages.write(pages, first_ref, :vamp)

    assert {pages, [{:write, "page-1", :vamp}]} = Pages.written(pages, "page-1")
    assert {pages, [{:write, "page-1", :a}]} = Pages.write(pages, first_ref, :a)
    assert {_pages, [{:write, "page-1", :b}]} = Pages.write(pages, retry_ref, :b)
  end

  test "turning the Page forgets the writes held for a Page that was never written" do
    {pages, page_ref} = opened()
    pages = Pages.page_closed(pages)
    {pages, []} = Pages.write(pages, page_ref, :track)

    pages = Pages.page_turned(pages)
    {pages, []} = Pages.write(pages, page_ref, :late_track)
    pages = pages |> Pages.page_opened(make_ref(), @astra) |> Pages.page_closed()

    assert {_pages, []} = Pages.written(pages, "page-2")
  end

  test "a written Page keeps taking writes after the Page has turned" do
    {pages, page_ref} = opened()
    giving = Pages.giving(pages)
    {pages, []} = Pages.written(pages, "page-1")

    pages = pages |> Pages.page_turned() |> Pages.page_opened(make_ref(), @astra)
    {pages, []} = Pages.written(pages, "page-2")

    assert {pages, [{:write, "page-1", :mask}]} = Pages.write(pages, giving, :mask)
    assert {_pages, [{:write, "page-1", :track}]} = Pages.write(pages, page_ref, :track)
  end

  test "a ref the Room never opened is dropped" do
    {pages, _page_ref} = opened()
    pages = Pages.page_closed(pages)

    assert {_pages, []} = Pages.write(pages, make_ref(), :stray)
  end

  test "the Assignment of the Page in play survives new Gives but not a turned Page" do
    assert Pages.assignment(Pages.new()) == nil

    {pages, _page_ref} = opened(@astra)
    assert Pages.assignment(pages) == @astra

    pages = Pages.gives_reset(pages)
    assert Pages.assignment(pages) == @astra

    pages = Pages.page_turned(pages)
    assert Pages.assignment(pages) == nil
  end
end
