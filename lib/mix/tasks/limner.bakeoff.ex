defmodule Mix.Tasks.Limner.Bakeoff do
  @moduledoc """
  Draws the same six Gives with each shortlisted Limner vendor and writes a
  contact sheet per vendor with milliseconds per image.

  Vendors: Recraft V4 Styles, Ideogram 3.0 turbo, FLUX.2 on Black Forest Labs.
  Against the Fake in tests; `--live` calls the vendors from the VPS.

  ## Options

    * `--dir`, `-d` - Destination directory (default: ".scratch/limner/bakeoff")
    * `--live` - Force live provider calls using environment API keys
    * `--fake` - Force Fake responses without network calls
    * `--deadline` - Per-image deadline in milliseconds (default: 60_000)

  ## Examples

      $ mix limner.bakeoff
      $ mix limner.bakeoff --dir .scratch/limner/bakeoff
      $ mix limner.bakeoff --live
  """
  use Mix.Task

  alias Thereish.Steward
  alias Thereish.Steward.Limner

  @shortdoc "Draws six Gives with each Limner vendor and writes contact sheets"

  @switches [
    dir: :string,
    live: :boolean,
    fake: :boolean,
    deadline: :integer
  ]

  @aliases [d: :dir]

  @default_dir ".scratch/limner/bakeoff"
  @default_deadline_ms 60_000

  @vendors [
    %{
      key: "recraft",
      name: "Recraft V4 Styles",
      module: Thereish.Steward.Recraft,
      model: "recraftv4_styles"
    },
    %{
      key: "ideogram",
      name: "Ideogram 3.0 turbo",
      module: Thereish.Steward.Ideogram,
      model: "ideogram-v3-turbo"
    },
    %{
      key: "bfl",
      name: "BFL FLUX.2",
      module: Thereish.Steward.Bfl,
      model: "flux-2-flex"
    }
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    dir = opts[:dir] || @default_dir
    File.mkdir_p!(dir)

    deadline_ms = opts[:deadline] || @default_deadline_ms
    gives = Limner.bakeoff_gives()

    fake? =
      cond do
        opts[:fake] -> true
        opts[:live] -> false
        Steward.adapter() == Thereish.Steward.Fake -> true
        true -> false
      end

    Mix.shell().info("""
    ================================================================================
    LIMNER BAKE-OFF: THE SAME SIX GIVES, THREE VENDORS
    ================================================================================
    Mode: #{if fake?, do: "Fake / Fixture (offline)", else: "LIVE (calling providers)"}
    Gives: #{gives |> Enum.map(&elem(&1, 0)) |> inspect()}
    Style: #{Limner.style_brief()}
    Output dir: #{Path.expand(dir)}
    """)

    results =
      Enum.reduce(@vendors, %{}, fn vendor, acc ->
        Mix.shell().info("--> #{vendor.name}")
        rows = run_vendor(vendor, gives, dir, fake?, deadline_ms)
        Map.put(acc, vendor.key, rows)
      end)

    write_reports(dir, gives, fake?, results)
    print_summary(results)
  end

  defp run_vendor(vendor, gives, dir, fake?, deadline_ms) do
    vendor_dir = Path.join(dir, vendor.key)
    File.mkdir_p!(vendor_dir)

    rows =
      gives
      |> Enum.with_index(1)
      |> Enum.map(fn {{give, colour}, index} ->
        Mix.shell().info("  [#{index}/#{length(gives)}] #{give}")
        row = draw_one(vendor, give, colour, fake?, deadline_ms)
        row = write_row_image(vendor_dir, index, give, row)
        Mix.shell().info("    #{format_row(row)}")
        row
      end)

    write_contact_sheet(vendor_dir, vendor, rows)
    rows
  end

  defp draw_one(vendor, give, colour, true, _deadline_ms) do
    started = System.monotonic_time(:millisecond)

    case Steward.draw(give, colour) do
      {:ok, mask} ->
        elapsed = System.monotonic_time(:millisecond) - started

        %{
          give: give,
          colour: colour,
          vendor: vendor.key,
          status: "ok",
          latency_ms: mask.meta[:latency_ms] || elapsed,
          cost_usd: mask.meta[:cost_usd],
          bytes: mask.bytes,
          format: mask.format,
          model: mask.meta[:model],
          file: nil
        }

      {:error, :refused} ->
        %{
          give: give,
          colour: colour,
          vendor: vendor.key,
          status: "refused",
          latency_ms: System.monotonic_time(:millisecond) - started,
          bytes: nil,
          file: nil
        }

      {:error, reason} ->
        %{
          give: give,
          colour: colour,
          vendor: vendor.key,
          status: "failed",
          error: inspect(reason),
          latency_ms: System.monotonic_time(:millisecond) - started,
          bytes: nil,
          file: nil
        }
    end
  end

  defp draw_one(vendor, give, colour, false, deadline_ms) do
    started = System.monotonic_time(:millisecond)
    prompt = Limner.prompt(give, colour)

    role = Steward.provider(:limner, nil, vendor.module).settings

    params =
      role
      |> Map.drop([:provider, :model])
      |> Map.put(:prompt, prompt)
      |> Map.put(:give, give)
      |> Map.put(:colour, colour)
      |> Map.put(:deadline_ms, deadline_ms)
      |> Map.put(:model, vendor.model)
      |> Map.put(:references, Limner.references(role))

    case vendor.module.generate(params) do
      {:ok, result} ->
        elapsed = System.monotonic_time(:millisecond) - started

        %{
          give: give,
          colour: colour,
          vendor: vendor.key,
          status: "ok",
          latency_ms: elapsed,
          cost_usd: result.cost_usd,
          bytes: result.bytes,
          format: result[:format] || :png,
          model: result.model,
          file: nil
        }

      {:error, :refused} ->
        %{
          give: give,
          colour: colour,
          vendor: vendor.key,
          status: "refused",
          latency_ms: System.monotonic_time(:millisecond) - started,
          bytes: nil,
          file: nil
        }

      {:error, reason} ->
        %{
          give: give,
          colour: colour,
          vendor: vendor.key,
          status: "failed",
          error: inspect(reason),
          latency_ms: System.monotonic_time(:millisecond) - started,
          bytes: nil,
          file: nil
        }
    end
  end

  defp write_row_image(_dir, _index, _give, %{bytes: bytes} = row) when not is_binary(bytes),
    do: row

  defp write_row_image(dir, index, give, row) do
    file = filename(index, give)
    File.write!(Path.join(dir, file), row.bytes)
    Map.put(row, :file, file)
  end

  defp filename(index, give) do
    slug =
      give
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    padded = index |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{padded}-#{slug}.png"
  end

  defp write_contact_sheet(dir, vendor, rows) do
    cells =
      Enum.map(Enum.with_index(rows, 1), fn {row, index} ->
        file = filename(index, row.give)

        img =
          if row[:bytes],
            do: ~s(<img src="#{file}" alt="#{esc(row.give)}" width="256" />),
            else: "—"

        ms = row[:latency_ms] || "—"

        """
        <figure>
          #{img}
          <figcaption>#{esc(row.give)} · #{row.status} · #{ms} ms</figcaption>
        </figure>
        """
      end)

    html = """
    <!doctype html>
    <meta charset="utf-8">
    <title>#{esc(vendor.name)}</title>
    <style>
      body { font-family: Georgia, serif; background: #1a1612; color: #e8dcc8; margin: 2rem; }
      h1 { font-weight: normal; }
      .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem; }
      figure { margin: 0; }
      img { width: 100%; height: auto; background: #111; display: block; }
      figcaption { margin-top: 0.5rem; font-size: 0.9rem; }
    </style>
    <h1>#{esc(vendor.name)}</h1>
    <p>#{esc(Limner.style_brief())}</p>
    <div class="grid">
    #{Enum.join(cells, "\n")}
    </div>
    """

    File.write!(Path.join(dir, "contact-sheet.html"), html)
  end

  defp esc(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp write_reports(dir, gives, fake?, results) do
    give_texts = Enum.map(gives, &elem(&1, 0))

    json_vendors =
      Map.new(results, fn {key, rows} ->
        {key, Enum.map(rows, &row_json/1)}
      end)

    report = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      fake: fake?,
      gives: give_texts,
      style_brief: Limner.style_brief(),
      vendors: json_vendors
    }

    File.write!(Path.join(dir, "report.json"), Jason.encode!(report, pretty: true) <> "\n")

    table =
      Enum.map(@vendors, fn vendor ->
        rows = results[vendor.key] || []
        lines = Enum.map(rows, &format_row/1)

        """
        #{vendor.name}
        #{Enum.join(lines, "\n")}
        """
      end)

    txt = """
    ================================================================================
    LIMNER BAKE-OFF REPORT
    ================================================================================
    Timestamp: #{report.timestamp}
    Mode: #{if fake?, do: "Fake / Fixture", else: "Live Providers"}
    Gives: #{Enum.join(give_texts, ", ")}

    Style: #{Limner.style_brief()}

    --------------------------------------------------------------------------------
    TIMINGS
    --------------------------------------------------------------------------------
    #{Enum.join(table, "\n")}
    """

    File.write!(Path.join(dir, "report.txt"), txt)
  end

  defp row_json(row) do
    %{
      "give" => row.give,
      "colour" => row.colour,
      "status" => row.status,
      "latency_ms" => row[:latency_ms],
      "cost_usd" => row[:cost_usd],
      "model" => row[:model],
      "file" => row[:file],
      "error" => row[:error]
    }
  end

  defp format_row(%{status: "ok"} = row) do
    cost = row[:cost_usd] || 0
    "  #{row.give}: #{row.latency_ms} ms · $#{cost}"
  end

  defp format_row(%{status: "refused"} = row) do
    "  #{row.give}: REFUSED (#{row[:latency_ms]} ms)"
  end

  defp format_row(row) do
    "  #{row.give}: FAILED #{row[:error]} (#{row[:latency_ms]} ms)"
  end

  defp print_summary(results) do
    header = "Vendor                          | Give              | Status  | ms"
    divider = String.duplicate("-", 78)

    lines =
      for vendor <- @vendors, row <- results[vendor.key] || [] do
        v = vendor.name |> String.slice(0, 30) |> String.pad_trailing(30)
        g = row.give |> String.slice(0, 17) |> String.pad_trailing(17)
        s = row.status |> String.pad_trailing(7)
        "#{v} | #{g} | #{s} | #{row[:latency_ms]}"
      end

    Mix.shell().info("""
    --------------------------------------------------------------------------------
    #{header}
    #{divider}
    #{Enum.join(lines, "\n")}
    --------------------------------------------------------------------------------
    """)
  end
end
