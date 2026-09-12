defmodule Thereish.Foley.PrologueTest do
  use ExUnit.Case, async: true

  alias Thereish.Foley.Prologue

  test "the script invites a Give, not a setting" do
    script = Prologue.script()

    assert script =~ "Give"
    refute script =~ "setting"
  end
end
