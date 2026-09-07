defmodule Thereish.Rooms.RateLimitTest do
  use ExUnit.Case, async: false

  alias Thereish.Rooms.RateLimit

  setup do
    prev = Application.get_env(:thereish, :room_creation_rate_limit)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:thereish, :room_creation_rate_limit, prev),
        else: Application.delete_env(:thereish, :room_creation_rate_limit)

      RateLimit.reset()
    end)

    RateLimit.reset()
    :ok
  end

  describe "in-memory sliding hour rate limit" do
    test "limits creations per device token" do
      # Configure limit of 3 for testing
      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 3,
        per_address: 10,
        window_seconds: 3600
      )

      device = "device-1"
      ip = "192.168.1.1"

      assert :ok = RateLimit.hit(device, ip)
      assert :ok = RateLimit.hit(device, ip)
      # 3rd is refused (limit is 3, so 3rd is the limit)
      assert {:error, :rate_limited} = RateLimit.hit(device, ip)
    end

    test "limits creations per remote address" do
      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 10,
        per_address: 2,
        window_seconds: 3600
      )

      ip = "10.0.0.1"

      assert :ok = RateLimit.hit("dev-1", ip)
      # 2nd is refused
      assert {:error, :rate_limited} = RateLimit.hit("dev-2", ip)
    end

    test "admits creations after sliding window expires" do
      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 2,
        per_address: 10,
        window_seconds: 100
      )

      device = "device-sliding"
      ip = "127.0.0.1"
      t0 = 1_000_000

      assert :ok = RateLimit.hit(device, ip, t0)
      assert {:error, :rate_limited} = RateLimit.hit(device, ip, t0 + 10)

      # After window (t0 + 101)
      assert :ok = RateLimit.hit(device, ip, t0 + 101)
    end

    test "a restart forgets the counts" do
      Application.put_env(:thereish, :room_creation_rate_limit,
        per_device: 2,
        per_address: 10,
        window_seconds: 3600
      )

      device = "device-restart"
      ip = "127.0.0.1"

      assert :ok = RateLimit.hit(device, ip)
      assert {:error, :rate_limited} = RateLimit.hit(device, ip)

      # Restart process
      Supervisor.terminate_child(Thereish.Supervisor, Thereish.Rooms.RateLimit)
      Supervisor.restart_child(Thereish.Supervisor, Thereish.Rooms.RateLimit)

      assert :ok = RateLimit.hit(device, ip)
    end
  end
end
