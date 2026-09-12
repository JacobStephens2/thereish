defmodule Thereish.Steward.Limner do
  @moduledoc """
  The Limner role: draws a Mask from one Give in the house style.

  The brief describes the look in words. A painter's name is what Jacob judges
  the bake-off by, not a token the prompt depends on — some vendors refuse them.
  """

  @style_brief """
  Cubist: the subject broken into overlapping planes seen from several angles at once. \
  A restrained palette of ochre, umber, grey, and bone on a dark ground. \
  Flat, poster-like, no text, no border. One subject centred and readable as a \
  silhouette at thumbnail size. Suggest the setting a step removed — an object or \
  figure it brings to mind, not a picture of the words themselves.
  """

  @doc "The house style brief the bake-off and every Mask share."
  @spec style_brief() :: String.t()
  def style_brief, do: String.trim(@style_brief)

  @palette [
    "#c4a35a",
    "#6b3a2a",
    "#8a9a6a",
    "#7a1f1f",
    "#d8c8a0",
    "#c45c5c",
    "#4a5c6a",
    "#b08968"
  ]

  @doc "The house colours from the style palette, one per Seat at the cap."
  @spec palette() :: [String.t()]
  def palette, do: @palette

  @doc "Builds a softened prompt for retrying after a refusal or error."
  @spec softened_prompt(String.t() | map(), String.t()) :: String.t()
  def softened_prompt(give, colour) when is_binary(colour) do
    prompt(give, colour, softened: true)
  end

  @doc """
  Builds the Limner's prompt from one Give and a Seat's colour.
  """
  @spec prompt(String.t() | map(), String.t(), keyword()) :: String.t()
  def prompt(give, colour, opts \\ []) when is_binary(colour) do
    text = Thereish.Steward.Author.give_text(give)
    softened = Keyword.get(opts, :softened, false)
    softened_note = if softened, do: " Softened, gentle, and abstract.", else: ""

    "A small square Mask. #{style_brief()} A note of #{colour} in the palette.#{softened_note} Setting: #{text}."
  end

  @doc "PNG magic number."
  @spec png?(binary()) :: boolean()
  def png?(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: true
  def png?(_), do: false

  @doc """
  Saves mask PNG bytes into the media directory and returns its web URL.
  """
  @spec store_mask(binary()) :: %{url: String.t(), path: String.t()}
  def store_mask(bytes) when is_binary(bytes) do
    hash = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    filename = "mask-#{hash}.png"
    dir = Path.join(Thereish.Steward.TrackCache.media_dir(), "masks")
    File.mkdir_p!(dir)
    file_path = Path.join(dir, filename)
    File.write!(file_path, bytes)
    web_path = "/media/masks/#{filename}"

    %{url: web_path, path: web_path}
  end

  @doc """
  Encodes a solid-colour RGB PNG of `size`×`size` pixels.

  Used by the Fake so tests and the bake-off's offline path have real image
  bytes without a vendor.
  """
  @spec png(String.t(), pos_integer()) :: binary()
  def png(colour, size \\ 64) when is_binary(colour) and size > 0 do
    {r, g, b} = rgb(colour)
    pixel = <<r, g, b>>
    scanline = <<0, :binary.copy(pixel, size)::binary>>
    raw = :binary.copy(scanline, size)
    compressed = :zlib.compress(raw)

    ihdr =
      chunk("IHDR", <<size::32, size::32, 8::8, 2::8, 0::8, 0::8, 0::8>>)

    idat = chunk("IDAT", compressed)
    iend = chunk("IEND", <<>>)

    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ihdr::binary, idat::binary, iend::binary>>
  end

  @doc "Parses a `#rrggbb` (or `rrggbb`) colour into an RGB triple."
  @spec rgb(String.t()) :: {byte(), byte(), byte()}
  def rgb("#" <> hex), do: rgb(hex)

  def rgb(<<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    {hex_byte(r), hex_byte(g), hex_byte(b)}
  end

  def rgb(_), do: {196, 92, 38}

  defp hex_byte(pair) do
    case Integer.parse(pair, 16) do
      {n, ""} when n in 0..255 -> n
      _ -> 0
    end
  end

  defp chunk(type, data) do
    crc = :erlang.crc32(type <> data)
    <<byte_size(data)::32, type::binary, data::binary, crc::32>>
  end

  @doc """
  Loads house reference images from the Limner role's `references` paths.

  Names are resolved under `priv/limner/references`. Missing files are skipped;
  an empty list is a Limner with no style anchor yet.
  """
  @spec references(map() | keyword()) :: [binary()]
  def references(role) when is_map(role), do: references(Map.to_list(role))

  def references(role) when is_list(role) do
    role
    |> Keyword.get(:references, [])
    |> List.wrap()
    |> Enum.flat_map(&read_reference/1)
  end

  defp read_reference(path) do
    resolved =
      cond do
        Path.type(path) == :absolute ->
          path

        File.exists?(path) ->
          path

        true ->
          Application.app_dir(
            :thereish,
            Path.join("priv/limner/references", Path.basename(path))
          )
      end

    case File.read(resolved) do
      {:ok, bytes} -> [bytes]
      _ -> []
    end
  end

  @doc "The six Gives the bake-off draws, including murder and Vecna."
  @spec bakeoff_gives() :: [{String.t(), String.t()}]
  def bakeoff_gives do
    [
      {"Liminal spaces", "#c4a35a"},
      {"Vecna", "#6b3a2a"},
      {"can of worms", "#8a9a6a"},
      {"murder", "#7a1f1f"},
      {"lighthouse", "#d8c8a0"},
      {"candy cane", "#c45c5c"}
    ]
  end
end
