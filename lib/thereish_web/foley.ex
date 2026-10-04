defmodule ThereishWeb.Foley do
  @moduledoc """
  Turns what Foley decides a screen plays into the events the browser's Foley
  hook listens for: the Cues between two of the Room's views, a Voice clip
  once Voice says it is ready, and the committing phone's own tick.
  """
  use ThereishWeb, :verified_routes

  import Phoenix.LiveView, only: [push_event: 3]

  alias Thereish.Foley.Cues

  @doc """
  Pushes the Cues `screen` plays as the Room's view moves from `old_room`
  (nil on the screen's first render) to `new_room`, each as the event the
  browser's Foley hook listens for.
  """
  def push_cues(socket, old_room, new_room, screen) do
    old_room
    |> Cues.between(new_room, screen)
    |> Enum.reduce(socket, fn cue, socket ->
      {event, payload} = event(cue)
      push_event(socket, event, payload)
    end)
  end

  @doc "The event name and payload the browser's Foley hook plays `cue` from."
  @spec event(Cues.cue()) :: {String.t(), map()}
  def event(:stop), do: {"foley:stop", %{}}
  def event({:stop_voice, attempt}), do: {"foley:stop_voice", %{attempt: attempt}}

  def event({:page, path, title, kind}),
    do: {"foley:page", %{path: path, title: title, kind: kind}}

  def event(:beat), do: {"foley:beat", %{}}
  def event({:sting, band}), do: {"foley:sting", %{band: band}}
  def event({:ending, kind}), do: {"foley:ending", %{kind: kind}}
  def event({:prologue, reading}), do: {"foley:prologue", %{path: reading}}
  def event(:stop_prologue), do: {"foley:stop_prologue", %{}}
  def event(:commit), do: {"foley:commit", %{}}

  @doc """
  Pushes a foley:own-commit event to the committing phone's view only when no
  Stage holds the Room. With a Stage present, the Stage sounds the commit and
  the phone stays quiet.
  """
  def push_own_commit(socket) do
    if Map.get(socket.assigns, :stage_present?, false) do
      socket
    else
      push_event(socket, "foley:own-commit", %{})
    end
  end

  @doc """
  Pushes a foley:voice event to the socket if this view is the speaker.

  `kind` is `:bookends` (Attempt announcement) or `:verdict` (Assayer at the reveal).
  """
  def push_voice(socket, attempt, kind \\ :verdict) do
    room = socket.assigns[:room]

    if room && Map.get(room, :speaker?) do
      url =
        case kind do
          :bookends -> ~p"/r/#{socket.assigns.slug}/voice/#{attempt}/bookends"
          _ -> ~p"/r/#{socket.assigns.slug}/voice/#{attempt}"
        end

      push_event(socket, "foley:voice", %{
        attempt: attempt,
        kind: to_string(kind),
        url: url
      })
    else
      socket
    end
  end
end
