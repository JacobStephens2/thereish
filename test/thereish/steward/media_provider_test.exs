defmodule Thereish.Steward.MediaProviderTest do
  use ExUnit.Case, async: false

  alias Thereish.Steward

  setup do
    steward = Application.fetch_env!(:thereish, :steward)
    on_exit(fn -> Application.put_env(:thereish, :steward, steward) end)
    :ok
  end

  describe "provider/2,3" do
    test "answers the configured module and its canonical name" do
      configure(:foley,
        jobs: [music: [provider: Steward.Mureka, api_key: "music-key"]]
      )

      assert %{module: Steward.Mureka, name: "mureka"} = Steward.provider(:foley, :music)
    end

    test "derives each provider's name from its module" do
      for {module, name} <- [
            {Steward.Hume, "hume"},
            {Steward.ElevenLabs, "eleven_labs"},
            {Steward.Mureka, "mureka"},
            {Steward.Lyria, "lyria"},
            {Steward.Apiframe, "apiframe"},
            {Steward.Recraft, "recraft"},
            {Steward.Fal, "fal"},
            {Steward.Bfl, "bfl"},
            {Steward.Ideogram, "ideogram"}
          ] do
        configure(:limner, provider: module)
        assert %{name: ^name} = Steward.provider(:limner)
      end
    end

    test "resolves the key from the job's own field" do
      configure(:foley,
        eleven_labs_api_key: "role-key",
        jobs: [effects: [provider: Steward.ElevenLabs, api_key: "job-key"]]
      )

      assert %{settings: %{api_key: "job-key"}, missing: []} =
               Steward.provider(:foley, :effects)
    end

    test "resolves the key from the vendor-scoped field on the role" do
      configure(:foley,
        hume_api_key: "hume-key",
        hume_secret_key: "hume-secret",
        jobs: [voice: [provider: Steward.Hume]]
      )

      assert %{settings: %{api_key: "hume-key", secret_key: "hume-secret"}, missing: []} =
               Steward.provider(:foley, :voice)
    end

    test "lists the environment variables of keys found nowhere, an empty string included" do
      configure(:foley,
        hume_api_key: "",
        jobs: [voice: [provider: Steward.Hume]]
      )

      assert %{settings: settings, missing: ["HUME_API_KEY", "HUME_SECRET_KEY"]} =
               Steward.provider(:foley, :voice)

      assert settings.api_key == nil
      assert settings.secret_key == nil
    end

    test "an override module answers in place of the configured one" do
      configure(:foley,
        eleven_labs_api_key: "eleven-key",
        jobs: [voice: [provider: Steward.Hume, voice_id: "v1"]]
      )

      assert %{module: Steward.ElevenLabs, name: "eleven_labs", settings: settings} =
               Steward.provider(:foley, :voice, Steward.ElevenLabs)

      assert settings.api_key == "eleven-key"
      assert settings.voice_id == "v1"
    end

    test "raises when the role names no provider" do
      configure(:limner, provider: nil)

      assert_raise ArgumentError, ~r/no provider/, fn -> Steward.provider(:limner) end
    end
  end

  defp configure(role, settings) do
    steward = Application.fetch_env!(:thereish, :steward)
    roles = Keyword.put(steward[:roles], role, settings)
    Application.put_env(:thereish, :steward, Keyword.put(steward, :roles, roles))
  end
end
