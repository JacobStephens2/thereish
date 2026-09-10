defmodule Thereish.Repo.Migrations.PruneDanglingTrackCacheRows do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Prunes rows in track_cache whose audio files do not exist on disk.
    # Runs once during deployment migrate step.
    execute(fn ->
      media_dir =
        Application.get_env(:thereish, :media_dir) ||
          Path.join([:code.priv_dir(:thereish) || "priv", "static", "media"])

      rows = repo().all(from(t in "track_cache", select: {t.id, t.path}))

      dangling_ids =
        Enum.filter(rows, fn {_id, path} ->
          case path do
            "/media/" <> rel -> not File.regular?(Path.join(media_dir, rel))
            nil -> true
            "" -> true
            p -> not File.regular?(Path.join(media_dir, p))
          end
        end)
        |> Enum.map(fn {id, _path} -> id end)

      count =
        if dangling_ids != [] do
          {deleted, _} =
            from(t in "track_cache", where: t.id in ^dangling_ids)
            |> repo().delete_all()

          deleted
        else
          0
        end

      case count do
        1 -> IO.puts("Pruned 1 dangling track_cache row")
        n -> IO.puts("Pruned #{n} dangling track_cache rows")
      end
    end)
  end

  def down do
    :ok
  end
end
