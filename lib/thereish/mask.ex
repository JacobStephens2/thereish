defmodule Thereish.Mask do
  @moduledoc """
  A Mask: the small picture the Limner draws from one Give, in its Seat's colour.

  One shape from the draw to every screen. A drawn Mask is `%Mask{url, meta}`,
  where `meta` is the Limner's provenance. A Seat whose Mask could not be drawn
  has `:dot` instead, and wears its colour's dot. The image bytes never leave
  the draw.

  It is also the `Ecto.Type` a Chronicle Page stores its Masks with, so every
  reader gets the same struct back. Load reads every shape stored before there
  was one: string or atom keys, meta kept flat beside the URL, the bytes, and
  the dot.
  """
  use Ecto.Type

  require Logger

  alias Thereish.Steward

  @enforce_keys [:url, :meta]
  defstruct [:url, :meta]

  @type t :: %__MODULE__{url: String.t() | nil, meta: map()}

  # The size every Room draws at.
  @size 512

  @doc """
  Draws a Seat's Mask from its Give and colour, or answers `:dot` when the
  Limner refuses, errors, raises or exits. Logs the failure and never raises.
  """
  @spec draw(String.t() | map(), String.t()) :: t() | :dot
  def draw(give, colour) do
    case Steward.draw(give, colour, size: @size) do
      {:ok, %{url: url, meta: meta}} when is_binary(url) ->
        %__MODULE__{url: url, meta: meta}

      {:error, reason} ->
        Logger.warning("Limner draw failed: #{inspect(reason, limit: 40)}")
        :dot
    end
  rescue
    error ->
      Logger.warning("Limner draw crashed: #{Exception.message(error)}")
      :dot
  catch
    :exit, reason ->
      Logger.warning("Limner draw exited: #{inspect(reason, limit: 20)}")
      :dot
  end

  @doc "A Mask's URL, or nil for the dot, a face-down Mask or no Mask at all."
  @spec url(term()) :: String.t() | nil
  def url(%__MODULE__{url: url}), do: url
  def url(_other), do: nil

  @impl Ecto.Type
  def type, do: :map

  # Inside a Page's `{:map, Mask}` the Mask is JSON, so it dumps and loads there
  # too rather than being encoded as it stands.
  @impl Ecto.Type
  def embed_as(_format), do: :dump

  @impl Ecto.Type
  def cast(%__MODULE__{} = mask), do: {:ok, mask}
  def cast(:dot), do: {:ok, :dot}
  def cast(_other), do: :error

  @impl Ecto.Type
  def dump(%__MODULE__{url: url, meta: meta}), do: {:ok, %{"url" => url, "meta" => meta}}
  def dump(:dot), do: {:ok, "dot"}
  def dump(_other), do: :error

  @impl Ecto.Type
  def load("dot"), do: {:ok, :dot}
  def load(:dot), do: {:ok, :dot}

  def load(row) when is_map(row) do
    url = Map.get(row, "url") || Map.get(row, :url)

    meta =
      Map.get(row, "meta") || Map.get(row, :meta) ||
        Map.drop(row, ["url", "path", "bytes", :url, :path, :bytes])

    {:ok, %__MODULE__{url: url, meta: meta}}
  end

  def load(_other), do: :error
end
