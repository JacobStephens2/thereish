defmodule ThereishWeb.DeviceToken do
  @moduledoc """
  Gives every browser a token, once, and keeps it in the signed session cookie.

  This is what "reopening the URL restores that Seat" is made of. The token
  identifies the *browser*, not the person: Melissa's Pixel and Jacob's phone
  each get their own, the laptop running the stage gets one it never uses, and
  the Room turns whichever token arrives into the Seat it holds.

  It lives in the session cookie rather than in `localStorage` because the dead
  render must already know who is asking — a token fetched by JavaScript would
  arrive one round trip after the page, so every phone would flash a name form
  it does not need. The cookie's `max_age` is set to a decade in
  `ThereishWeb.Endpoint`, because Seats never expire and neither should the
  shortcut back to one.
  """
  @behaviour Plug

  @key "device_token"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn =
      case Plug.Conn.get_session(conn, @key) do
        nil -> Plug.Conn.put_session(conn, @key, mint())
        _token -> conn
      end

    ip_string =
      case conn.remote_ip do
        ip when is_tuple(ip) -> ip |> :inet.ntoa() |> to_string()
        _ -> nil
      end

    if ip_string do
      Plug.Conn.put_session(conn, "remote_ip", ip_string)
    else
      conn
    end
  end

  @doc """
  The token in a LiveView's session map.

  A missing token is a wiring mistake, not a visitor without one, so it raises
  rather than minting a replacement. A LiveView cannot set a cookie, so a token
  minted here would be forgotten before the next request and every visit would
  quietly take a fresh Seat.
  """
  def from_session(%{@key => token}) when is_binary(token), do: token

  def from_session(_session) do
    raise "no device token in the session: is #{inspect(__MODULE__)} in the browser pipeline?"
  end

  defp mint, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
