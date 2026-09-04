# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias MeaningGame.Pages

chapter = "suburban family life"

pages = [
  %{
    page_id: "P-SUB-01",
    chapter: chapter,
    theme: "the backyard barbecue",
    give: nil,
    anchors: ["backyard", "weekend"],
    bait: "barbecue",
    deep_bridges: ["lawnmower", "chores", "sprinkler"],
    likely_bridges: [
      "barbecue",
      "lawnmower",
      "chores",
      "sprinkler",
      "hammock",
      "patio",
      "charcoal"
    ],
    why_these:
      "Backyard and weekend instantly suggest barbecue as the social trap. Lawnmower and chores represent the domestic duty underneath; sprinkler captures the nostalgic childhood texture.",
    band_scripts: %{
      "miss" => "Different neighbourhoods entirely.",
      "adjacent" => "On the same block, across the street.",
      "near" => "In the same backyard.",
      "meld" => "You both smelled the grill.",
      "deep_meld" => "Two minds at the mower."
    },
    meta: %{
      model: "claude-fable-5-1",
      prompt_version: "author-1",
      attempts: 1,
      cost_usd: 0.12,
      latency_ms: 54_000
    }
  },
  %{
    page_id: "P-SUB-02",
    chapter: chapter,
    theme: "the morning rush",
    give: nil,
    anchors: ["kitchen", "clock"],
    bait: "breakfast",
    deep_bridges: ["backpack", "toast"],
    likely_bridges: [
      "breakfast",
      "backpack",
      "toast",
      "tardiness",
      "coffee",
      "cereal",
      "lunchbox"
    ],
    why_these:
      "Kitchen and clock point straight to breakfast as the routine anchor. Backpack and lunchbox capture the frantic exit; toast is the rushed compromise.",
    band_scripts: %{
      "miss" => "Sleeping through the alarm.",
      "adjacent" => "Passing each other in the hallway.",
      "near" => "At the counter together.",
      "meld" => "Both reaching for the cereal.",
      "deep_meld" => "Packed and out the door in unison."
    },
    meta: %{
      model: "claude-fable-5-1",
      prompt_version: "author-1",
      attempts: 1,
      cost_usd: 0.13,
      latency_ms: 61_000
    }
  },
  %{
    page_id: "P-SUB-03",
    chapter: chapter,
    theme: "the family road trip",
    give: nil,
    anchors: ["highway", "minivan"],
    bait: "vacation",
    deep_bridges: ["luggage", "snacks"],
    likely_bridges: ["vacation", "luggage", "snacks", "detour", "rest", "playlist", "traffic"],
    why_these:
      "Highway and minivan trigger the grand ambition of vacation. Snacks and luggage are the tactical reality; detour is the shared narrative pivot.",
    band_scripts: %{
      "miss" => "Headed in opposite directions.",
      "adjacent" => "In the slow lane together.",
      "near" => "At the same highway exit.",
      "meld" => "Eyes on the destination.",
      "deep_meld" => "Sharing the front-seat secret."
    },
    meta: %{
      model: "claude-fable-5-1",
      prompt_version: "author-1",
      attempts: 1,
      cost_usd: 0.14,
      latency_ms: 58_000
    }
  },
  %{
    page_id: "P-SUB-04",
    chapter: chapter,
    theme: "the garage sanctuary",
    give: nil,
    anchors: ["workbench", "shelf"],
    bait: "toolbox",
    deep_bridges: ["cobweb", "project"],
    likely_bridges: ["toolbox", "cobweb", "project", "nostalgia", "hammer", "clutter", "paint"],
    why_these:
      "Workbench and shelf invite toolbox as the immediate functional association. Cobweb and nostalgia evoke the unfinished summer tasks and forgotten relics.",
    band_scripts: %{
      "miss" => "Rummaging in the wrong bin.",
      "adjacent" => "On adjoining pegboards.",
      "near" => "Hovering over the same project.",
      "meld" => "Both grabbing the wrench.",
      "deep_meld" => "Unspoken reverence for unfinished work."
    },
    meta: %{
      model: "claude-fable-5-1",
      prompt_version: "author-1",
      attempts: 1,
      cost_usd: 0.11,
      latency_ms: 49_000
    }
  }
]

Enum.each(pages, fn page_attrs ->
  case Pages.insert_page(page_attrs) do
    {:ok, page} ->
      IO.puts("Seeded Page #{page.id}: #{page.chapter} (#{page.theme})")

    {:error, changeset} ->
      # Ignore if already seeded
      IO.puts("Skipping #{page_attrs.page_id || page_attrs[:id]} (#{inspect(changeset.errors)})")
  end
end)
