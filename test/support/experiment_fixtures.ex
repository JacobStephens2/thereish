defmodule Thereish.ExperimentFixtures do
  @moduledoc """
  Seeds the A/B harness's rows straight into Postgres, for tests that need an
  assignment or an outcome the Room did not play.

  The game only ever writes these through `Thereish.Experiments`, which
  assigns an arm when the Author is asked and records an outcome from a
  closed Page's Entry. A test that wants twenty completed outcomes, or an
  assignment of the retired Bait against plain experiment, inserts the schema
  rows here instead.

  It also reads the rows back, so a test can see what `Thereish.Experiments`
  recorded without the harness keeping its queries public for it.
  """

  import Ecto.Query

  alias Thereish.Chronicle.ExperimentAssignment
  alias Thereish.Chronicle.BookendsTap
  alias Thereish.Chronicle.ExperimentOutcome
  alias Thereish.Chronicle.ExperimentUnblinding
  alias Thereish.Repo

  @doc """
  Inserts one arm assignment. Every field but the Room has a default.
  """
  def insert_assignment(room_id, attrs \\ %{}) do
    defaults = %{
      page_identifier: "page-#{System.unique_integer([:positive])}",
      experiment_id: "author_model",
      arm: "flash",
      chapter: "harbour",
      assigned_at: DateTime.utc_now()
    }

    %ExperimentAssignment{}
    |> ExperimentAssignment.changeset(
      defaults
      |> Map.merge(Map.new(attrs))
      |> Map.put(:room_id, room_id)
    )
    |> Repo.insert!()
  end

  @doc """
  Inserts one completed-Page outcome: a one-Attempt Meld unless told otherwise.
  """
  def insert_outcome(room_id, attrs \\ %{}) do
    defaults = %{
      page_identifier: "page-#{System.unique_integer([:positive])}",
      experiment_id: "author_model",
      arm: "flash",
      melded: true,
      closeness: 80,
      attempts_count: 1,
      closed_because: "meld"
    }

    %ExperimentOutcome{}
    |> ExperimentOutcome.changeset(
      defaults
      |> Map.merge(Map.new(attrs))
      |> Map.put(:room_id, room_id)
    )
    |> Repo.insert!()
  end

  @doc """
  Inserts `count` completed-Page outcomes of one experiment, toward its
  declared sample.
  """
  def insert_outcomes(room_id, experiment_id, count, attrs \\ %{}) when count > 0 do
    arm = if experiment_id == "bait_against_plain", do: "bait", else: "flash"

    for _ <- 1..count do
      insert_outcome(
        room_id,
        Map.merge(%{experiment_id: experiment_id, arm: arm}, Map.new(attrs))
      )
    end
  end

  @doc "A Room's assignments of one experiment, oldest first."
  def assignments(room_id, experiment_id) do
    from(a in ExperimentAssignment,
      where: a.room_id == ^room_id and a.experiment_id == ^experiment_id,
      order_by: [asc: a.assigned_at, asc: a.id]
    )
    |> Repo.all()
  end

  @doc "A Room's outcomes of one experiment, oldest first."
  def outcomes(room_id, experiment_id) do
    from(o in ExperimentOutcome,
      where: o.room_id == ^room_id and o.experiment_id == ^experiment_id,
      order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> Repo.all()
  end

  @doc "A Room's Bookends taps, oldest first."
  def bookends_taps(room_id) do
    from(t in BookendsTap,
      where: t.room_id == ^room_id,
      order_by: [asc: t.inserted_at, asc: t.id]
    )
    |> Repo.all()
  end

  @doc "Whether the experiment, or any experiment when none is named, is unblinded in the Room."
  def unblinded?(room_id, experiment_id \\ nil) do
    query = from(u in ExperimentUnblinding, where: u.room_id == ^room_id)
    query = if experiment_id, do: where(query, experiment_id: ^experiment_id), else: query
    Repo.exists?(query)
  end
end
