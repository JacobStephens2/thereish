defmodule ThereishWeb.AdminComponents do
  @moduledoc """
  Markup for authenticated operator views.
  """
  use ThereishWeb, :html

  attr :room, :map, required: true
  attr :unblinded, :boolean, required: true
  attr :progress, :map, required: true
  attr :readout, :map, required: true

  def experiment_card(assigns) do
    ~H"""
    <section
      data-role="experiment-card"
      data-slug={@room.slug}
      data-experiment={@readout.experiment.id}
      class="flex flex-col gap-3 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm"
    >
      <div class="flex items-start justify-between gap-2 border-b border-base-200 pb-3">
        <div>
          <div class="flex items-center gap-2">
            <span class="text-xs font-bold uppercase tracking-wider opacity-60">
              {@room.slug}
            </span>
            <span
              :if={!@unblinded}
              data-role="blinded-banner"
              class="rounded-full bg-base-200 px-2.5 py-0.5 text-xs font-semibold opacity-70"
            >
              Blinded during play
            </span>
            <span
              :if={@unblinded}
              data-role="unblinded-banner"
              class="rounded-full bg-primary/20 px-2.5 py-0.5 text-xs font-semibold text-primary"
            >
              Deliberately Unblinded
            </span>
          </div>
          <h2 class="text-xl font-bold tracking-tight mt-1">{@readout.experiment.name}</h2>
          <p class="text-xs opacity-70 mt-0.5">
            {@readout.experiment.description} Declared sample size: {@readout.experiment.sample_size} Pages.
          </p>
          <p data-role="experiment-progress" class="text-sm mt-2">
            {@progress.recorded} / {@progress.required} completed Pages
          </p>
        </div>
        <div>
          <button
            :if={!@unblinded}
            phx-click="unblind_experiment"
            phx-value-room-id={@room.id}
            phx-value-experiment-id={@readout.experiment.id}
            disabled={!@progress.ready?}
            data-role="unblind-button"
            class="rounded-lg bg-neutral px-3 py-1.5 text-xs font-semibold text-neutral-content hover:opacity-90 cursor-pointer disabled:cursor-not-allowed disabled:opacity-40"
          >
            Unblind Experiment
          </button>
        </div>
      </div>

      <div class="text-xs opacity-75">
        <p :if={@readout.experiment.id == "author_model"}>
          <span class="font-semibold">Declared outcomes:</span>
          Meld rate, attempts to meld, bookends preferences (flat / fine / great), and closing band distribution.
        </p>
        <p :if={@readout.experiment.id == "channel"}>
          <span class="font-semibold">Declared outcomes:</span>
          Meld rate, attempts to meld, closing band distribution, and bookends preferences (flat / fine / great).
        </p>
        <p :if={@readout.experiment.id == "bait_against_plain"}>
          <span class="font-semibold">Declared outcomes:</span>
          Meld rate, attempts to meld, fairness preferences, overrules, and bait trap convergence.
        </p>
      </div>

      <div
        :if={@unblinded && @readout}
        data-role="experiment-readout"
        class="flex flex-col gap-3 mt-1 pt-3 border-t border-base-200"
      >
        <h3 class="text-sm font-bold uppercase tracking-wider opacity-70">Qualitative Readout</h3>

        <div
          :if={@readout.experiment.id == "author_model"}
          class="grid grid-cols-1 sm:grid-cols-2 gap-3"
        >
          <.arm_readout_card
            data_role="readout-arm-flash"
            title="Gemini 3.8 Flash"
            title_class="text-secondary"
            summary={@readout.flash}
          >
            <div>
              Best streak: <span class="font-semibold">{@readout.flash.longest_meld_streak}</span>
            </div>
            <div class="mt-1 opacity-75">Preferences: {@readout.flash.preferences_summary}</div>
            <div
              :if={@readout.flash[:closing_bands] && map_size(@readout.flash.closing_bands) > 0}
              class="mt-0.5 opacity-60 text-[11px]"
            >
              Bands: {Enum.map_join(@readout.flash.closing_bands, ", ", fn {k, v} ->
                "#{k}: #{v}"
              end)}
            </div>
          </.arm_readout_card>

          <.arm_readout_card
            data_role="readout-arm-astra"
            title="GPT-6 Astra"
            title_class="opacity-80"
            summary={@readout.astra}
          >
            <div>
              Best streak: <span class="font-semibold">{@readout.astra.longest_meld_streak}</span>
            </div>
            <div class="mt-1 opacity-75">Preferences: {@readout.astra.preferences_summary}</div>
            <div
              :if={@readout.astra[:closing_bands] && map_size(@readout.astra.closing_bands) > 0}
              class="mt-0.5 opacity-60 text-[11px]"
            >
              Bands: {Enum.map_join(@readout.astra.closing_bands, ", ", fn {k, v} ->
                "#{k}: #{v}"
              end)}
            </div>
          </.arm_readout_card>
        </div>

        <div
          :if={@readout.experiment.id == "channel"}
          class="grid grid-cols-1 sm:grid-cols-2 gap-3"
        >
          <.arm_readout_card
            data_role="readout-arm-nudge-on"
            title="Pages with a Nudge"
            title_class="text-secondary"
            summary={@readout.nudge_on}
          >
            <div>
              Best streak: <span class="font-semibold">{@readout.nudge_on.longest_meld_streak}</span>
            </div>
            <div class="mt-1 opacity-75">Preferences: {@readout.nudge_on.preferences_summary}</div>
          </.arm_readout_card>

          <.arm_readout_card
            data_role="readout-arm-nudge-off"
            title="Pages without one"
            title_class="opacity-80"
            summary={@readout.nudge_off}
          >
            <div>
              Best streak: <span class="font-semibold">{@readout.nudge_off.longest_meld_streak}</span>
            </div>
            <div class="mt-1 opacity-75">Preferences: {@readout.nudge_off.preferences_summary}</div>
          </.arm_readout_card>
        </div>

        <div
          :if={@readout.experiment.id == "bait_against_plain"}
          class="grid grid-cols-1 sm:grid-cols-2 gap-3"
        >
          <.arm_readout_card
            data_role="readout-arm-bait"
            title="Bait-scored Pages"
            title_class="text-secondary"
            summary={@readout.bait}
          >
            <div>
              Traps sprung: <span class="font-semibold">{@readout.bait.trap_sprung_count}</span>
            </div>
            <div class="mt-1 opacity-75">Fairness: {@readout.bait.fairness_summary}</div>
          </.arm_readout_card>

          <.arm_readout_card
            data_role="readout-arm-plain"
            title="Plain Pages"
            title_class="opacity-80"
            summary={@readout.plain}
          >
            <div>
              Overrules: <span class="font-semibold">{@readout.plain.overrules_count}</span>
            </div>
            <div class="mt-1 opacity-75">Fairness: {@readout.plain.fairness_summary}</div>
          </.arm_readout_card>
        </div>

        <div
          data-role="readout-narrative"
          class="rounded-lg bg-base-200/30 p-3 text-xs italic opacity-90 border border-base-300/50"
        >
          "{@readout.summary_narrative}"
        </div>
      </div>
    </section>
    """
  end

  attr :data_role, :string, required: true
  attr :title, :string, required: true
  attr :title_class, :string, default: "opacity-80"
  attr :summary, :map, required: true
  slot :inner_block, required: true

  defp arm_readout_card(assigns) do
    ~H"""
    <div data-role={@data_role} class="rounded-lg bg-base-200/60 p-3 flex flex-col gap-1 text-xs">
      <span class={["font-bold text-sm", @title_class]}>{@title}</span>
      <div>Pages played: <span class="font-semibold">{@summary.pages_count}</span></div>
      <div>Meld rate: <span class="font-semibold">{@summary.meld_rate}</span></div>
      <div>
        Mean attempts: <span class="font-semibold">{@summary.mean_attempts_to_meld}</span>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
