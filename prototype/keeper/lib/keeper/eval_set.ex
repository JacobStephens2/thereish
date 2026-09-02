defmodule Keeper.EvalSet do
  @moduledoc "Twenty hand-made Mind-Meld submissions, obvious-match to clear-miss. `expect` is Jacob's-agent prior, not ground truth."

  @items [
    %{id: 1, anchors: ["ocean", "night"], a: "moon", b: "moon", expect: "100 identical"},
    %{id: 2, anchors: ["ocean", "night"], a: "tide", b: "tides", expect: "~100 inflection"},
    %{id: 3, anchors: ["mirror", "river"], a: "reflection", b: "reflect", expect: "~95"},
    %{id: 4, anchors: ["coffee", "morning"], a: "cup", b: "mug", expect: "~90 synonyms"},
    %{id: 5, anchors: ["fire", "ice"], a: "melt", b: "thaw", expect: "~90 synonyms"},
    %{id: 6, anchors: ["garden", "prison"], a: "wall", b: "fence", expect: "~80 near"},
    %{id: 7, anchors: ["bread", "knife"], a: "butter", b: "spread", expect: "~75 borderline meld"},
    %{id: 8, anchors: ["king", "castle"], a: "throne", b: "crown", expect: "~70 related"},
    %{id: 9, anchors: ["ocean", "night"], a: "tide", b: "moon", expect: "~55 related"},
    %{id: 10, anchors: ["coffee", "morning"], a: "alarm", b: "awake", expect: "~60 related"},
    %{id: 11, anchors: ["fire", "ice"], a: "water", b: "steam", expect: "~60 related"},
    %{id: 12, anchors: ["doctor", "silence"], a: "waiting", b: "hospital", expect: "~45"},
    %{id: 13, anchors: ["doctor", "silence"], a: "oath", b: "secret", expect: "~50"},
    %{id: 14, anchors: ["letter", "wound"], a: "open", b: "seal", expect: "~35 antonym-ish"},
    %{id: 15, anchors: ["train", "dream"], a: "journey", b: "sleep", expect: "~30"},
    %{id: 16, anchors: ["king", "castle"], a: "moat", b: "queen", expect: "~30"},
    %{id: 17, anchors: ["train", "dream"], a: "track", b: "drift", expect: "~25"},
    %{id: 18, anchors: ["letter", "wound"], a: "paper", b: "scar", expect: "~15 miss"},
    %{id: 19, anchors: ["garden", "prison"], a: "weed", b: "cell", expect: "~15 miss"},
    %{id: 20, anchors: ["mirror", "river"], a: "glass", b: "bank", expect: "~10 miss"}
  ]

  def items, do: @items
  def item(id), do: Enum.find(@items, &(&1.id == id))

  def submission(item), do: %{"anchors" => item.anchors, "words" => %{"A" => item.a, "B" => item.b}}
  def page(item), do: %{"id" => "P-eval-#{item.id}", "kind" => "mindmeld", "theme" => "eval set", "anchors" => item.anchors}
end
