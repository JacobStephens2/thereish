defmodule ThereishWeb.Plugs.ForwardedAddress do
  @moduledoc """
  Rewrites the connection address from `X-Forwarded-For` when the peer is the
  trusted proxy hop, and leaves every other peer alone.

  The hop is loopback, or the bridge gateway that dials the published app port.
  The rest of the bridge subnet is not that hop: any other peer keeps its own
  address. `RemoteIp` reads only `X-Forwarded-For`,
  which the proxy has already replaced with the browser that connected.
  """
  @behaviour Plug

  # Packed once. `RemoteIp.call/2` expects options from `init/1`; a bare
  # keyword leaves the other options unset. Only this header is read, so a
  # caller cannot pick the address with `X-Real-Ip` or `Forwarded`.
  @remote_ip RemoteIp.init(headers: ["x-forwarded-for"])

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if trusted_hop?(conn.remote_ip) do
      RemoteIp.call(conn, @remote_ip)
    else
      conn
    end
  end

  @doc """
  The bridge gateway that dials the published app port, or `nil` outside the
  app container.

  Inside the container that gateway is the default route. The host's own
  default route is a different hop and is not trusted.
  """
  def discover_bridge_gateway do
    if File.exists?("/.dockerenv") do
      case File.read("/proc/net/route") do
        {:ok, table} -> bridge_gateway(table)
        _ -> nil
      end
    else
      nil
    end
  end

  @doc """
  The default-route gateway in a `/proc/net/route` table.

  That address is the one docker uses to dial the published port. A route for
  the subnet itself has no gateway and is not it.
  """
  def bridge_gateway(route_table) when is_binary(route_table) do
    route_table
    |> String.split("\n", trim: true)
    |> Enum.find_value(&default_gateway/1)
  end

  defp trusted_hop?({127, _, _, _}), do: true
  defp trusted_hop?({0, 0, 0, 0, 0, 0, 0, 1}), do: true

  defp trusted_hop?(ip) when is_tuple(ip),
    do: ip == Application.get_env(:thereish, :bridge_gateway)

  defp trusted_hop?(_), do: false

  defp default_gateway(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [_iface, "00000000", gateway | _] -> decode_gateway(gateway)
      _ -> nil
    end
  end

  defp decode_gateway("00000000"), do: nil

  defp decode_gateway(<<hex::binary-size(8)>>) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<a, b, c, d>>} -> {d, c, b, a}
      _ -> nil
    end
  end

  defp decode_gateway(_), do: nil
end
