defmodule Thereish.Repo.Migrations.AnchorsBecomeBookends do
  use Ecto.Migration

  def change do
    rename table(:chronicle_attempts), :anchors, to: :bookends
    rename table(:chronicle_fairness_taps), :anchors, to: :bookends
    rename table(:precedents), :anchors, to: :bookends
    rename table(:chronicle_overrules), :anchors, to: :bookends
    rename table(:authored_pages), :anchors, to: :bookends
  end
end
