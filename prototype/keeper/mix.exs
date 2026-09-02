defmodule Keeper.MixProject do
  # PROTOTYPE — throwaway. See README.md.
  use Mix.Project

  def project do
    [
      app: :keeper,
      version: "0.0.1-prototype",
      elixir: "~> 1.19",
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:jsv, "~> 0.22"}
    ]
  end
end
