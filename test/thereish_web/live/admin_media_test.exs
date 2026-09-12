defmodule ThereishWeb.AdminMediaTest do
  @moduledoc """
  Authenticated browsing of retained Tracks, Vamps, and Masks (ticket 13).
  """
  use ThereishWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Rooms
  alias Thereish.Rooms.Room
  alias Thereish.Steward.TrackCache

  describe "the gallery is an operator page" do
    test "an unauthenticated visitor is sent to sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/sign-in"}}} = live(conn, ~p"/admin/media")
    end

    test "the overview links through to an empty gallery", %{conn: conn} do
      conn = log_in_admin(conn)
      {:ok, overview, html} = live(conn, ~p"/admin")

      assert has_element?(overview, "a[href='/admin/media']", "Media")
      refute html =~ "/admin/rooms"
      refute html =~ "/admin/timing"

      {:ok, gallery, gallery_html} = live(conn, ~p"/admin/media")

      assert has_element?(gallery, "[data-role=admin-gallery]")
      assert gallery_html =~ ~r/<meta[^>]*robots[^>]*noindex/i
      assert has_element?(gallery, "[data-role=gallery-empty]")
      refute has_element?(gallery, "[data-role=gallery-track]")
      refute has_element?(gallery, "[data-role=gallery-vamp]")
      refute has_element?(gallery, "[data-role=gallery-mask]")
      assert has_element?(gallery, "a[href='/admin']")
    end
  end

  describe "retained Tracks and Vamps" do
    setup %{conn: conn} do
      media_dir = unique_media_dir()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      %{
        conn: log_in_admin(conn),
        media_dir: media_dir,
        slug: slug,
        mara: mara,
        jacob: jacob
      }
    end

    test "a Page's Track and Vamp are both playable with Room and Page provenance",
         %{conn: conn, slug: slug} = ctx do
      track_path = write_media("tracks/harbour-lights.mp3")
      vamp_path = write_media("vamps/harbour-vamp.mp3")

      write_closed_page(ctx,
        page: %{"bookends" => ["lantern", "harbour"]},
        music_meta: %{path: track_path, title: "Harbour Lights"},
        vamp_meta: %{path: vamp_path, duration: 30, loop: true}
      )

      {:ok, view, html} = live(conn, ~p"/admin/media")

      refute has_element?(view, "[data-role=gallery-empty]")

      assert has_element?(
               view,
               ~s([data-role=gallery-track] audio[data-role=track-player][src="#{track_path}"])
             )

      assert html =~ "Harbour Lights"

      assert has_element?(
               view,
               ~s([data-role=gallery-vamp] audio[data-role=vamp-player][src="#{vamp_path}"][loop])
             )

      vamp_html = render(element(view, "[data-role=gallery-vamp]"))
      assert vamp_html =~ "Vamp"
      assert vamp_html =~ "short"

      assert has_element?(view, "[data-role=gallery-track] [data-role=gallery-provenance]", slug)
      assert has_element?(view, "[data-role=gallery-vamp] [data-role=gallery-provenance]", slug)

      assert has_element?(
               view,
               ~s([data-role=gallery-track] a[href="/r/#{slug}/chronicle"])
             )

      track_html = render(element(view, "[data-role=gallery-track]"))
      assert track_html =~ "lantern"
      assert track_html =~ "harbour"
    end

    test "the ordinary Chronicle still plays the same Page's Track and Vamp",
         %{conn: conn, slug: slug} = ctx do
      track_path = "/media/tracks/harbour-lights.mp3"
      vamp_path = "/media/vamps/harbour-vamp.mp3"

      {:ok, page} =
        write_closed_page(ctx,
          page: %{"bookends" => ["lantern", "harbour"]},
          music_meta: %{path: track_path, title: "Harbour Lights"},
          vamp_meta: %{path: vamp_path, loop: true}
        )

      {:ok, _gallery, _} = live(conn, ~p"/admin/media")
      {:ok, book, _} = live(build_conn(), ~p"/r/#{slug}/chronicle")

      assert has_element?(
               book,
               ~s([data-role=chronicle-page][data-page-id="#{page.id}"] [data-role=track] audio[src="#{track_path}"])
             )

      assert has_element?(
               book,
               ~s([data-role=chronicle-page][data-page-id="#{page.id}"] [data-role=vamp] audio[src="#{vamp_path}"])
             )
    end
  end

  describe "Masks" do
    setup %{conn: conn} do
      media_dir = unique_media_dir()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      %{
        conn: log_in_admin(conn),
        media_dir: media_dir,
        slug: slug,
        mara: mara,
        jacob: jacob
      }
    end

    test "a Mask enlarges and closes, including historical artwork",
         %{conn: conn, slug: slug} = ctx do
      historical = write_media("masks/mask-historical.png")
      current = write_media("masks/mask-mara.png")

      write_closed_page(ctx,
        page: %{"bookends" => ["desert", "oasis"]},
        masks: %{
          ctx.mara.id => %{url: historical},
          ctx.jacob.id => %{url: current}
        }
      )

      {:ok, view, _html} = live(conn, ~p"/admin/media")

      refute has_element?(view, "[data-role=gallery-empty]")
      assert has_element?(view, "[data-role=gallery-mask] [data-role=enlarge-mask]")
      refute has_element?(view, "[data-role=enlarged-mask]")

      view
      |> element("[data-role=enlarge-mask][data-url='#{historical}']")
      |> render_click()

      assert has_element?(view, "[data-role=enlarged-mask]")

      assert has_element?(
               view,
               "[data-role=enlarged-mask-image][src='#{historical}']"
             )

      assert has_element?(view, "[data-role=close-enlarged-mask][aria-label='Close']")

      view |> element("[data-role=close-enlarged-mask]") |> render_click()
      refute has_element?(view, "[data-role=enlarged-mask]")

      view
      |> element("[data-role=enlarge-mask][data-url='#{current}']")
      |> render_click()

      assert has_element?(
               view,
               "[data-role=enlarged-mask-image][src='#{current}']"
             )

      assert has_element?(view, "[data-role=gallery-mask] [data-role=gallery-provenance]", slug)
    end
  end

  describe "legacy and missing records" do
    setup %{conn: conn} do
      media_dir = unique_media_dir()
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      %{
        conn: log_in_admin(conn),
        media_dir: media_dir,
        slug: slug,
        mara: mara,
        jacob: jacob
      }
    end

    test "an unassociated Track still appears without an invented Page", %{conn: conn} do
      path = write_media("tracks/orphan-cache.mp3")

      {:ok, _} =
        TrackCache.put(["unassociated give #{System.unique_integer([:positive])}"], %{
          title: "Orphan Cache",
          path: path,
          duration: 120,
          format: :mp3,
          meta: %{}
        })

      {:ok, view, _html} = live(conn, ~p"/admin/media")

      assert has_element?(
               view,
               ~s([data-role=gallery-track] audio[data-role=track-player][src="#{path}"])
             )

      assert render(element(view, "[data-role=gallery-track]")) =~ "Orphan Cache"
      assert has_element?(view, "[data-role=gallery-track] [data-role=unassociated]")
      refute has_element?(view, "[data-role=gallery-track] [data-role=gallery-provenance]")
    end

    test "a missing file is shown honestly and the record is kept",
         %{conn: conn, slug: slug} = ctx do
      write_closed_page(ctx,
        page: %{"bookends" => ["lantern", "harbour"]},
        music_meta: %{path: "/media/tracks/gone-harbour.mp3", title: "Gone Harbour"},
        vamp_meta: %{path: "/media/vamps/gone-vamp.mp3", loop: true},
        masks: %{ctx.mara.id => %{url: "/media/masks/gone-mask.png"}}
      )

      {:ok, view, _html} = live(conn, ~p"/admin/media")

      assert has_element?(view, "[data-role=gallery-track] [data-role=missing-media]")
      refute has_element?(view, "[data-role=gallery-track] audio[data-role=track-player]")
      assert render(element(view, "[data-role=gallery-track]")) =~ "Gone Harbour"
      assert has_element?(view, "[data-role=gallery-track] [data-role=gallery-provenance]", slug)

      assert has_element?(view, "[data-role=gallery-vamp] [data-role=missing-media]")
      refute has_element?(view, "[data-role=gallery-vamp] audio[data-role=vamp-player]")

      assert has_element?(view, "[data-role=gallery-mask] [data-role=missing-media]")
      refute has_element?(view, "[data-role=gallery-mask] [data-role=enlarge-mask]")

      {:ok, again, _} = live(conn, ~p"/admin/media")
      assert has_element?(again, "[data-role=gallery-track] [data-role=missing-media]")
      assert has_element?(again, "[data-role=gallery-vamp] [data-role=missing-media]")
      assert has_element?(again, "[data-role=gallery-mask] [data-role=missing-media]")
    end
  end

  defp unique_media_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "thereish-admin-media-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    previous = Application.get_env(:thereish, :media_dir)
    Application.put_env(:thereish, :media_dir, dir)

    ExUnit.Callbacks.on_exit(fn ->
      if previous do
        Application.put_env(:thereish, :media_dir, previous)
      else
        Application.delete_env(:thereish, :media_dir)
      end

      File.rm_rf(dir)
    end)

    dir
  end

  defp write_media(rel) do
    path = "/media/#{rel}"
    full = TrackCache.disk_path(path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, "audio-bytes")
    path
  end

  defp write_closed_page(ctx, attrs) do
    attrs = Map.new(attrs)
    room = Repo.get_by!(Room, slug: ctx.slug)
    bookends = attrs[:bookends] || ["lantern", "harbour"]

    entry =
      Map.merge(
        %{
          page: %{"bookends" => bookends},
          closed_because: :meld,
          melded?: true,
          closeness: 95,
          attempts: [
            %{
              number: 1,
              bookends: bookends,
              closeness: 95,
              melded?: true,
              bridges: [
                %{seat_id: ctx.mara.id, bridge: "lighthouse"},
                %{seat_id: ctx.jacob.id, bridge: "lighthouse"}
              ],
              verdicts: []
            }
          ]
        },
        Map.drop(attrs, [:bookends])
      )

    Chronicle.write(room.id, entry, DateTime.utc_now())
  end
end
