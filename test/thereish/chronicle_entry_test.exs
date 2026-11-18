defmodule Thereish.ChronicleEntryTest do
  use Thereish.DataCase, async: false

  import Thereish.EntryFixtures
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Experiments
  alias Thereish.Rooms
  alias Thereish.Rooms.Store

  setup do
    code = open_room()
    {:ok, mara} = Rooms.join(code, "Mara", device_token())
    {:ok, jacob} = Rooms.join(code, "Jacob", device_token())
    %{room: Store.get_room(code), mara: mara, jacob: jacob}
  end

  describe "one complete Entry write" do
    for rejected <- [:primary, :secondary] do
      test "a rejected #{rejected} Arm rolls back the Page and every play row", ctx do
        {:ok, _existing} =
          Chronicle.write(ctx.room.id, complete_entry(ctx, Experiments.assign(ctx.room.id)))

        assignment = Experiments.assign(ctx.room.id)
        [channel] = assignment.also

        assignment =
          case unquote(rejected) do
            :primary -> %{assignment | arm: :invalid}
            :secondary -> %{assignment | also: [%{channel | arm: :invalid}]}
          end

        before = recorded_rows()

        assert_raise Ecto.InvalidChangesetError, fn ->
          Chronicle.write(ctx.room.id, complete_entry(ctx, assignment))
        end

        assert recorded_rows() == before
      end
    end

    test "an Assignment link rejected after both outcomes rolls back the complete Entry", ctx do
      {:ok, _existing} =
        Chronicle.write(ctx.room.id, complete_entry(ctx, Experiments.assign(ctx.room.id)))

      assignment = Experiments.assign(ctx.room.id)
      before = recorded_rows()

      Repo.query!("""
      CREATE FUNCTION pg_temp.reject_entry_link() RETURNS trigger AS $$
      BEGIN
        IF (SELECT count(*) FROM chronicle_experiment_outcomes WHERE page_id = NEW.page_id) = 2
        THEN
          RAISE EXCEPTION 'Assignment link rejected after both outcomes' USING ERRCODE = '23514';
        END IF;
        RAISE EXCEPTION 'Assignment link attempted before both outcomes';
      END
      $$ LANGUAGE plpgsql
      """)

      Repo.query!("""
      CREATE TRIGGER reject_entry_link BEFORE UPDATE ON chronicle_experiment_assignments
      FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_entry_link()
      """)

      try do
        assert_raise Postgrex.Error, ~r/Assignment link rejected after both outcomes/, fn ->
          Chronicle.write(ctx.room.id, complete_entry(ctx, assignment))
        end

        assert recorded_rows() == before
      after
        Repo.query!("DROP TRIGGER reject_entry_link ON chronicle_experiment_assignments")
        Repo.query!("DROP FUNCTION pg_temp.reject_entry_link()")
      end

      # Removing the scoped fault permits exactly the same retained Assignment.
      assert {:ok, _page} = Chronicle.write(ctx.room.id, complete_entry(ctx, assignment))
    end
  end

  defp recorded_rows do
    for schema <- [
          Chronicle.Page,
          Chronicle.Give,
          Chronicle.Attempt,
          Chronicle.Bridge,
          Chronicle.Verdict,
          Chronicle.ExperimentOutcome,
          Chronicle.ExperimentAssignment
        ],
        into: %{} do
      {schema, Repo.all(from(row in schema, order_by: row.id))}
    end
  end

  defp complete_entry(ctx, assignment) do
    entry(
      assignment: assignment,
      gives: [%{seat_id: ctx.mara.id, text: "lighthouse"}],
      attempts: [
        %{
          bridges: [
            %{seat_id: ctx.mara.id, bridge: "beacon"},
            %{seat_id: ctx.jacob.id, bridge: "beacon"}
          ],
          verdicts: [
            %{
              seat_ids: [ctx.mara.id, ctx.jacob.id],
              bridges: ["beacon", "beacon"]
            }
          ]
        }
      ]
    )
  end
end
