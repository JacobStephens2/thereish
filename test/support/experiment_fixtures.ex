defmodule Thereish.ExperimentFixtures do
  @moduledoc """
  Seeds the A/B harness's rows straight into Postgres, for tests that need an
  assignment or an outcome the Room did not play.

  The game only ever writes these through `Thereish.Experiments`, which
  assigns an arm when the Author is asked and records an outcome from a
  closed Page's Entry. A test that wants twenty completed outcomes, or an
  assignment of the retired Bait against plain experiment, inserts the schema
  rows here instead.
  """

  alias Thereish.Chronicle.ExperimentAssignment
  alias Thereish.Chronicle.ExperimentOutcome
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
end
