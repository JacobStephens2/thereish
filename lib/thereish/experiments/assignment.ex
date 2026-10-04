defmodule Thereish.Experiments.Assignment do
  @moduledoc """
  The Arm an Experiment gives one Page, as `Thereish.Experiments.assign/1`
  hands it out when the Author is asked for the Page: the assignment row's
  id, its Experiment's id and its Arm.

  The Room carries it with the Page until the Page's outcome is recorded, and
  reads nothing from it but the Arm, which is the Author's job. A Page whose
  assignment could not be recorded carries the default Arm and no id, and
  links no row.
  """

  @enforce_keys [:experiment_id, :arm]
  defstruct [:id, :experiment_id, :arm]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          experiment_id: String.t(),
          arm: atom()
        }
end
