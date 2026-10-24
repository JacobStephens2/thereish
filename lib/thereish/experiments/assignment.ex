defmodule Thereish.Experiments.Assignment do
  @moduledoc """
  The Arm an Experiment gives one Page, as `Thereish.Experiments.assign/1`
  hands it out when the Author is asked for the Page: the assignment row's
  id, its Experiment's id and its Arm.

  The Room carries it with the Page until the Page's outcome is recorded. A
  Page whose Assignment could not be recorded carries the default Arm and no
  id, and links no row.

  A Page is assigned by every live Experiment at once, each alternating on its
  own rows, so `also` carries the rest of them beside the one the Room was
  handed. The Room reads an Arm by naming its Experiment (`arm/2`) rather than
  by trusting which Experiment came first: the Author's job is one Arm, and the
  Page's Nudge budget is another.
  """

  @enforce_keys [:experiment_id, :arm]
  defstruct [:id, :experiment_id, :arm, also: []]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          experiment_id: String.t(),
          arm: atom(),
          also: [t()]
        }

  @doc """
  The Arm a Page plays under in one named Experiment, or nil when that
  Experiment did not assign the Page — which is what a Page from before an
  Experiment existed answers, and what the default Assignment answers for
  every Experiment but its own.
  """
  @spec arm(t() | nil, atom() | String.t()) :: atom() | nil
  def arm(nil, _experiment_id), do: nil

  def arm(%__MODULE__{} = assignment, experiment_id) do
    wanted = to_string(experiment_id)

    Enum.find_value([assignment | assignment.also], &(&1.experiment_id == wanted && &1.arm))
  end
end
