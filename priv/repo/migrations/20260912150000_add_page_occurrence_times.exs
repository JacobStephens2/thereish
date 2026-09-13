defmodule Thereish.Repo.Migrations.AddPageOccurrenceTimes do
  use Ecto.Migration

  def change do
    alter table(:chronicle_pages) do
      add :revealed_at, :utc_datetime_usec
    end

    alter table(:chronicle_gives) do
      add :arrived_at, :utc_datetime_usec
    end

    alter table(:chronicle_attempts) do
      add :started_at, :utc_datetime_usec
      add :assaying_started_at, :utc_datetime_usec
      add :revealed_at, :utc_datetime_usec
      add :advanced_at, :utc_datetime_usec
    end
  end
end
