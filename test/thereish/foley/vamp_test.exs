defmodule Thereish.Foley.VampTest do
  @moduledoc """
  A Page's Vamp has one shape from Foley's result to the Chronicle: a `%Vamp{}`
  stored flat through its own type (ticket 201).
  """
  use ExUnit.Case, async: true

  alias Thereish.Foley.Vamp

  @vamp %{
    path: "/media/vamps/a.mp3",
    duration: 30,
    format: :mp3,
    loop: true,
    meta: %{provider: "fake", model: "fake-vamp", cost_usd: 0.0, latency_ms: 5, loop: true}
  }

  describe "landed/1" do
    test "a Vamp carries its path, duration, format, loop and provenance with string keys" do
      assert Vamp.landed(@vamp) == %Vamp{
               path: "/media/vamps/a.mp3",
               duration: 30,
               format: "mp3",
               loop: true,
               meta: %{
                 "provider" => "fake",
                 "model" => "fake-vamp",
                 "cost_usd" => 0.0,
                 "latency_ms" => 5
               }
             }
    end

    test "loops unless the result says otherwise" do
      assert Vamp.landed(Map.delete(@vamp, :loop)).loop == true
      assert Vamp.landed(%{@vamp | loop: false}).loop == false
    end
  end

  describe "kept?/1" do
    test "a Vamp with a path is kept; one without, and no Vamp, are not" do
      assert Vamp.kept?(Vamp.landed(@vamp))
      refute Vamp.kept?(%Vamp{path: "", meta: %{}})
      refute Vamp.kept?(nil)
    end
  end

  describe "as an Ecto.Type" do
    test "dumps flat with string keys, omitting nil fields" do
      vamp = Vamp.landed(%{path: "/v.mp3", meta: %{model: "m"}})

      assert Ecto.Type.dump(Vamp, vamp) ==
               {:ok, %{"path" => "/v.mp3", "loop" => true, "model" => "m"}}
    end

    test "a Vamp round-trips through dump, JSON and load" do
      vamp = Vamp.landed(@vamp)

      assert {:ok, dumped} = Ecto.Type.dump(Vamp, vamp)
      json = dumped |> Jason.encode!() |> Jason.decode!()
      assert vamp |> Jason.encode!() |> Jason.decode!() == json
      assert Ecto.Type.load(Vamp, json) == {:ok, vamp}
    end

    test "loads a stored row with string keys" do
      row = %{"path" => "/v.mp3", "duration" => 30, "loop" => true, "model" => "m"}

      assert Ecto.Type.load(Vamp, row) ==
               {:ok, %Vamp{path: "/v.mp3", duration: 30, loop: true, meta: %{"model" => "m"}}}
    end

    test "loads a row with atom keys" do
      row = %{path: "/v.mp3", format: "mp3", loop: false, model: "m"}

      assert Ecto.Type.load(Vamp, row) ==
               {:ok, %Vamp{path: "/v.mp3", format: "mp3", loop: false, meta: %{"model" => "m"}}}
    end

    test "loads a row written with every key twice" do
      row = %{:path => "/v.mp3", "path" => "/v.mp3", :loop => true, "loop" => true}

      assert Ecto.Type.load(Vamp, row) == {:ok, %Vamp{path: "/v.mp3", loop: true, meta: %{}}}
    end

    test "casts only a Vamp" do
      vamp = Vamp.landed(@vamp)

      assert Ecto.Type.cast(Vamp, vamp) == {:ok, vamp}
      assert Ecto.Type.cast(Vamp, nil) == {:ok, nil}
      assert Ecto.Type.cast(Vamp, %{"path" => "/v.mp3"}) == :error
    end
  end
end
