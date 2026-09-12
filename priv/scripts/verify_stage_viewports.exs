alias Thereish.Rooms
alias Thereish.Rooms.Server
alias Thereish.Rooms.Store

# Ensure Sandbox is in shared mode for external HTTP requests
Ecto.Adapters.SQL.Sandbox.mode(Thereish.Repo, :manual)
:ok = Ecto.Adapters.SQL.Sandbox.checkout(Thereish.Repo)
Ecto.Adapters.SQL.Sandbox.mode(Thereish.Repo, {:shared, self()})

defmodule Helper do
  def create_room(opts) do
    slug = "test-#{System.unique_integer([:positive])}"
    seat_limit = Keyword.get(opts, :seat_limit, Rooms.default_seat_limit())
    {:ok, _room} = Store.insert_room(slug, seat_limit)
    {:ok, pid} = Server.start_link(slug: slug)
    {slug, pid}
  end

  def join(slug, name) do
    token = "dev-#{name}-#{System.unique_integer([:positive])}"
    Rooms.join(slug, name, token)
  end

  def set_steward(opts) do
    steward = Application.fetch_env!(:thereish, :steward)
    fake = Keyword.merge(Keyword.get(steward, :fake, []), opts)
    Application.put_env(:thereish, :steward, Keyword.put(steward, :fake, fake))
  end

  def set_author_timing(delay_ms, timeout_ms) do
    steward = Application.fetch_env!(:thereish, :steward)
    fake = Keyword.merge(Keyword.get(steward, :fake, []), author_delay_ms: delay_ms, author_mode: :ok)
    roles = Keyword.get(steward, :roles, [])
    author = Keyword.get(roles, :author, [])
    author = Keyword.merge(author, timeout_ms: timeout_ms, deadline_ms: timeout_ms)
    roles = Keyword.put(roles, :author, author)
    steward = steward |> Keyword.put(:fake, fake) |> Keyword.put(:roles, roles)
    Application.put_env(:thereish, :steward, steward)

    escalation =
      if delay_ms > 0 do
        [still_writing: timeout_ms, deadline: timeout_ms * 2]
      else
        [still_writing: 100, deadline: 250]
      end

    Application.put_env(:thereish, :author_escalation_ms, escalation)
  end

  def set_assayer_timing(delay_ms, timeout_ms) do
    steward = Application.fetch_env!(:thereish, :steward)
    fake = Keyword.merge(Keyword.get(steward, :fake, []), delay_ms: delay_ms)
    roles = Keyword.get(steward, :roles, [])
    assayer = Keyword.get(roles, :assayer, [])
    assayer = Keyword.merge(assayer, timeout_ms: timeout_ms, deadline_ms: timeout_ms)
    roles = Keyword.put(roles, :assayer, assayer)
    steward = steward |> Keyword.put(:fake, fake) |> Keyword.put(:roles, roles)
    Application.put_env(:thereish, :steward, steward)

    escalation =
      if delay_ms > 0 do
        [slow: timeout_ms, unavailable: timeout_ms * 2]
      else
        [slow: 100, unavailable: 250]
      end

    Application.put_env(:thereish, :assayer_escalation_ms, escalation)
  end

  def set_beat(ms) do
    Application.put_env(:thereish, :reveal_beat_ms, ms)
  end

  def set_attempt_cap(cap) do
    Application.put_env(:thereish, :attempts_per_page, cap)
  end

  def await_phase(slug, phase) do
    eventually(fn ->
      view = Thereish.Rooms.snapshot(slug, nil)
      view.phase == phase && view
    end, "the Room never reached #{inspect(phase)}")
  end

  def await_reveal(slug) do
    eventually(fn ->
      view = Thereish.Rooms.snapshot(slug, nil)
      view.reveal != nil && view
    end, "the reveal never landed in this Room")
  end

  def eventually(check, what \\ "the thing being waited for never happened") do
    deadline = System.monotonic_time(:millisecond) + 5_000
    keep_trying(check, what, deadline)
  end

  defp keep_trying(check, what, deadline) do
    cond do
      result = check.() ->
        result
      System.monotonic_time(:millisecond) > deadline ->
        raise what
      true ->
        Process.sleep(10)
        keep_trying(check, what, deadline)
    end
  end

  def run_audit(url, w, h, shot_path, selectors) do
    selectors_json = Jason.encode!(selectors)
    args = ["priv/scripts/viewport_audit.mjs", url, to_string(w), to_string(h), shot_path, selectors_json]
    case System.cmd("node", args, stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✓ PASSED: #{w}x#{h} -> #{shot_path}")
        {:ok, output}
      {output, status} ->
        IO.puts("✗ FAILED (#{status}): #{w}x#{h} -> #{shot_path}\n#{output}")
        {:error, output}
    end
  end
end

viewports = [
  {1512, 908},
  {1366, 768}
]

port = System.get_env("TEST_PORT") || "4002"
base_url = "http://localhost:#{port}"
screenshot_dir = ".scratch/at-the-table"
File.mkdir_p!(screenshot_dir)

# 1. Reveal with 3 bridges
IO.puts("\nSetting up: Reveal with 3 bridges...")
{slug1, _} = Helper.create_room(seat_limit: 3)
{:ok, s1} = Helper.join(slug1, "Melissa")
{:ok, s2} = Helper.join(slug1, "Jacob")
{:ok, s3} = Helper.join(slug1, "Ada")
Rooms.give(slug1, s1.id, "candlelit cathedral")
Rooms.give(slug1, s2.id, "misty forest")
Rooms.give(slug1, s3.id, "ancient library")
Helper.await_phase(slug1, :bridging)
Rooms.commit_bridge(slug1, s1.id, "cairn")
Rooms.commit_bridge(slug1, s2.id, "cairo")
Rooms.commit_bridge(slug1, s3.id, "beacon")
Helper.await_reveal(slug1)

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_reveal_3bridges.png")
  expected = [
    "header h1",
    "[data-role=attempt]",
    "[data-role=bookends]",
    "[data-role=comparison]",
    "[data-role=closeness]",
    "[data-role=band]",
    "[data-role=quip]",
    "[data-role=stage-foot]",
    "[data-role=join-url]",
    "[data-role=roster]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug1}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end

# 2. Reveal with 8 bridges (seat cap)
IO.puts("\nSetting up: Reveal with 8 bridges (seat cap)...")
{slug2, _} = Helper.create_room(seat_limit: 8)
seats8 = for name <- ["Melissa", "Jacob", "Ada", "Sam", "Noah", "Lily", "Ivy", "Ned"] do
  {:ok, s} = Helper.join(slug2, name)
  s
end
for {s, i} <- Enum.with_index(seats8) do
  Rooms.give(slug2, s.id, "setting #{i}")
end
Helper.await_phase(slug2, :bridging)
bridges8 = ["cairn", "cairo", "beacon", "drift", "compass", "anchor", "stone", "flare"]
for {s, b} <- Enum.zip(seats8, bridges8) do
  Rooms.commit_bridge(slug2, s.id, b)
end
Helper.await_reveal(slug2)

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_reveal_8bridges.png")
  expected = [
    "header h1",
    "[data-role=attempt]",
    "[data-role=bookends]",
    "[data-role=comparison]",
    "[data-role=closeness]",
    "[data-role=band]",
    "[data-role=quip]",
    "[data-role=stage-foot]",
    "[data-role=join-url]",
    "[data-role=roster]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug2}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end

# 3. Giving phase
IO.puts("\nSetting up: Giving phase...")
{slug3, _} = Helper.create_room(seat_limit: 2)
{:ok, _} = Helper.join(slug3, "Melissa")
{:ok, _} = Helper.join(slug3, "Jacob")

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_giving.png")
  expected = [
    "header h1",
    "[data-role=giving-stage]",
    "[data-role=stage-foot]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug3}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end

# 4. Writing phase
IO.puts("\nSetting up: Writing phase...")
{slug4, _} = Helper.create_room(seat_limit: 2)
Helper.set_author_timing(30_000, 60_000)
{:ok, s4_1} = Helper.join(slug4, "Melissa")
{:ok, s4_2} = Helper.join(slug4, "Jacob")
Rooms.give(slug4, s4_1.id, "setting 1")
Rooms.give(slug4, s4_2.id, "setting 2")
Helper.await_phase(slug4, :writing)

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_writing.png")
  expected = [
    "header h1",
    "[data-role=writing-stage]",
    "[data-role=stage-foot]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug4}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end
Helper.set_author_timing(0, 2_000)

# 5. Bridging phase
IO.puts("\nSetting up: Bridging phase...")
{slug5, _} = Helper.create_room(seat_limit: 2)
{:ok, s5_1} = Helper.join(slug5, "Melissa")
{:ok, s5_2} = Helper.join(slug5, "Jacob")
Rooms.give(slug5, s5_1.id, "lanterns on the quay")
Rooms.give(slug5, s5_2.id, "fog over the harbour")
Helper.await_phase(slug5, :bridging)

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_bridging.png")
  expected = [
    "header h1",
    "[data-role=attempt]",
    "[data-role=bookends]",
    "[data-role=stage-foot]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug5}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end

# 6. Assaying phase (the beat)
IO.puts("\nSetting up: Assaying phase...")
{slug6, _} = Helper.create_room(seat_limit: 2)
Helper.set_assayer_timing(30_000, 60_000)
Helper.set_beat(30_000)
{:ok, s6_1} = Helper.join(slug6, "Melissa")
{:ok, s6_2} = Helper.join(slug6, "Jacob")
Rooms.give(slug6, s6_1.id, "setting A")
Rooms.give(slug6, s6_2.id, "setting B")
Helper.await_phase(slug6, :bridging)
Rooms.commit_bridge(slug6, s6_1.id, "cairn")
Rooms.commit_bridge(slug6, s6_2.id, "cairo")
Helper.await_phase(slug6, :assaying)

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_assaying.png")
  expected = [
    "header h1",
    "[data-role=attempt]",
    "[data-role=bookends]",
    "[data-role=phase][data-step=grading]",
    "[data-role=stage-foot]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug6}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end
Helper.set_assayer_timing(0, 1_000)
Helper.set_beat(5)

# 7. Closed phase (ending line and arc)
IO.puts("\nSetting up: Closed phase...")
Helper.set_attempt_cap(2)
{slug7, _} = Helper.create_room(seat_limit: 2)
{:ok, s7_1} = Helper.join(slug7, "Melissa")
{:ok, s7_2} = Helper.join(slug7, "Jacob")
Rooms.give(slug7, s7_1.id, "first give")
Rooms.give(slug7, s7_2.id, "second give")
Helper.await_phase(slug7, :bridging)
# Attempt 1 (miss)
Rooms.commit_bridge(slug7, s7_1.id, "cairn")
Rooms.commit_bridge(slug7, s7_2.id, "beacon")
Helper.await_reveal(slug7)
# Advance to attempt 2
Rooms.next_attempt(slug7, s7_1.id)
Helper.await_phase(slug7, :bridging)
# Attempt 2 (meld -> closes page with arc of played attempt 1)
Rooms.commit_bridge(slug7, s7_1.id, "compass")
Rooms.commit_bridge(slug7, s7_2.id, "compass")
Helper.await_phase(slug7, :closed)

for {w, h} <- viewports do
  shot = Path.join(screenshot_dir, "stage_#{w}x#{h}_closed.png")
  expected = [
    "header h1",
    "[data-role=ending]",
    "[data-role=ending-line]",
    "[data-role=arc]",
    "[data-role=stage-foot]"
  ]
  case Helper.run_audit("#{base_url}/r/#{slug7}/stage", w, h, shot, expected) do
    {:ok, _} -> :ok
    _ -> Process.exit(self(), :audit_failed)
  end
end

IO.puts("\n==========================================")
IO.puts("ALL VIEWPORT AUDITS AND SCREENSHOTS PASSED!")
IO.puts("==========================================")
