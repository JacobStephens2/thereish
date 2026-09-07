defmodule Thereish.Steward.ValeTest do
  @moduledoc """
  The one place in the codebase that shells out, and the only test that does.

  Vale is a pinned project tool (`mise.toml`), so these run everywhere the suite
  runs. A machine without it is a machine where the gate is not installed, which
  is a thing these tests should say out loud rather than skip past.
  """
  use ExUnit.Case, async: true

  alias Thereish.Steward.Vale

  describe "prose the Scribe is allowed to write" do
    test "a recap in the players' own words passes" do
      assert :ok =
               Vale.check(
                 ~s(Three attempts to find the word between "lantern" and "harbour", and ) <>
                   ~s(Melissa got there first with "guide". Jacob had written "keeper", ) <>
                   ~s(which is the same idea wearing a coat.)
               )
    end

    test "quoting a Bridge with straight quotes is not a typography fault" do
      assert :ok = Vale.check(~s(Jacob wrote "cairn" and Melissa wrote "beacon".))
    end
  end

  describe "prose the gate refuses" do
    test "a recap longer than the book has room for" do
      long = String.duplicate("The couple wrote a word between the bookends again. ", 12)

      assert {:error, why} = Vale.check(long)
      assert why =~ "Scribe.Length"
    end

    test "the words that give a model away" do
      assert {:error, why} =
               Vale.check(
                 "What a journey this Page was, a rich tapestry and a true testament " <>
                   "to how they delve into the bookends together."
               )

      assert why =~ "Scribe.Grandiose"
    end

    test "an em dash" do
      assert {:error, why} = Vale.check("Jacob wrote cairn — Melissa wrote beacon.")
      assert why =~ "AiTells.Dash"
    end

    test "restating the Assayer's grade" do
      assert {:error, why} =
               Vale.check(
                 "They wrote marker and mark, and the Assayer scored them 82 out of 100."
               )

      assert why =~ "Scribe.Verdict"
    end

    test "an exclamation mark" do
      assert {:error, why} = Vale.check("Jacob and Melissa both wrote marker!")
      assert why =~ "Scribe.Exclaim"
    end

    test "the epigram machine" do
      assert {:error, why} =
               Vale.check(
                 "It is not just a game of words, it's a way of listening to each other."
               )

      assert why =~ "Scribe.NotJust"
    end

    test "blank prose is not prose" do
      assert {:error, why} = Vale.check("   \n  ")
      assert why =~ "blank"
    end
  end

  describe "what the gate reports" do
    test "every alert is named, so the repair pass has something to fix" do
      assert {:error, why} =
               Vale.check("What a journey! The Assayer scored them well.")

      assert why =~ "Scribe.Grandiose"
      assert why =~ "Scribe.Exclaim"
      assert why =~ "Scribe.Verdict"
    end

    test "the gate says it is installed" do
      assert Vale.installed?()
    end
  end
end
