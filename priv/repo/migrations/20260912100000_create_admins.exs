defmodule Thereish.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  def up do
    create table(:admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:admins, [:email])

    create table(:admin_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :admin_id, references(:admins, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:admin_tokens, [:admin_id])
    create unique_index(:admin_tokens, [:context, :token])

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    execute("""
    INSERT INTO admins (id, email, hashed_password, inserted_at, updated_at)
    VALUES (
      '#{Ecto.UUID.generate()}',
      'jacob@stephens.page',
      NULL,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    )
    """)
  end

  def down do
    drop table(:admin_tokens)
    drop table(:admins)
  end
end
