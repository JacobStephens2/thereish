defmodule ThereishWeb.ForwardedAddressTest do
  @moduledoc """
  The address a request is charged as, after the endpoint has seen it.

  The public proxy replaces X-Forwarded-For with the browser that connected.
  That header rewrites the connection only when the peer is the trusted hop:
  loopback, or the bridge gateway that dials the published app port. Any other
  peer keeps its own address.
  """
  use ThereishWeb.ConnCase, async: true

  @gateway {172, 17, 0, 1}
  @bridge_neighbor {172, 17, 0, 50}
  @browser {203, 0, 113, 5}

  test "a loopback peer is rewritten to the forwarded browser address", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-forwarded-for", "203.0.113.5")
      |> put_req_header("x-real-ip", "198.51.100.4")
      |> get(~p"/new")

    assert conn.remote_ip == @browser
  end

  test "the bridge gateway is rewritten to the forwarded browser address", %{conn: conn} do
    conn =
      %{conn | remote_ip: @gateway}
      |> put_req_header("x-forwarded-for", "203.0.113.5")
      |> get(~p"/new")

    assert conn.remote_ip == @browser
  end

  test "another address on the bridge subnet keeps its own address", %{conn: conn} do
    conn =
      %{conn | remote_ip: @bridge_neighbor}
      |> put_req_header("x-forwarded-for", "203.0.113.5")
      |> get(~p"/new")

    assert conn.remote_ip == @bridge_neighbor
  end

  test "any other peer keeps its own address and ignores the forwarded one", %{conn: conn} do
    conn =
      %{conn | remote_ip: {203, 0, 113, 9}}
      |> put_req_header("x-forwarded-for", "198.51.100.4")
      |> get(~p"/new")

    assert conn.remote_ip == {203, 0, 113, 9}
  end

  test "ipv6 loopback is rewritten to the forwarded browser address", %{conn: conn} do
    conn =
      %{conn | remote_ip: {0, 0, 0, 0, 0, 0, 0, 1}}
      |> put_req_header("x-forwarded-for", "203.0.113.5")
      |> get(~p"/new")

    assert conn.remote_ip == @browser
  end

  test "the bridge gateway is the default route, not another route on the subnet" do
    table = """
    Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT
    eth0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0
    eth0\t00000000\t010011AC\t0003\t0\t0\t0\t00000000\t0\t0\t0
    """

    assert ThereishWeb.Plugs.ForwardedAddress.bridge_gateway(table) == @gateway
  end

  test "a route table with no default route has no bridge gateway" do
    table = "eth0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0\n"

    assert ThereishWeb.Plugs.ForwardedAddress.bridge_gateway(table) == nil
  end

  test "outside the app container the host default route is not a trusted hop" do
    if File.exists?("/.dockerenv") do
      assert is_tuple(ThereishWeb.Plugs.ForwardedAddress.discover_bridge_gateway())
    else
      assert ThereishWeb.Plugs.ForwardedAddress.discover_bridge_gateway() == nil
    end
  end
end
