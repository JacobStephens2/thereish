import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/thereish start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :thereish, ThereishWeb.Endpoint, server: true
end

# Not in :test — the suite boots a real endpoint on the port config/test.exs
# names, and this would otherwise silently move it to 4000.
if config_env() != :test do
  config :thereish, ThereishWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end

# Inside the app container the default route is the bridge gateway that dials
# the published port. That hop may name the browser. The host's own default
# route is not that hop, and the rest of the bridge subnet is not either.
if gateway = ThereishWeb.Plugs.ForwardedAddress.discover_bridge_gateway() do
  config :thereish, :bridge_gateway, gateway
end

# The Assayer's key, in every environment that has one. It is set here rather
# than read where it is used so that a key is configuration like the model and
# the effort are, and so that nothing goes looking at the environment in the
# middle of a reveal. A missing key is not fatal: the game says it has no
# verdict, loudly, and the couple make the call.
if key = System.get_env("GEMINI_API_KEY") do
  config :thereish, :steward,
    roles: [
      assayer: [api_key: key],
      author: [api_key: key],
      scribe: [jobs: [naming: [api_key: key], title: [api_key: key]]],
      foley: [lyria_api_key: key, jobs: [ear: [api_key: key]]]
    ]
end

if key = System.get_env("OPENAI_API_KEY") do
  config :thereish, :steward,
    roles: [
      author: [jobs: [astra: [api_key: key]]]
    ]
end

if key = System.get_env("ANTHROPIC_API_KEY") do
  config :thereish, :steward,
    roles: [
      scribe: [jobs: [recap: [api_key: key]]]
    ]
end

if key = System.get_env("ELEVENLABS_API_KEY") do
  config :thereish, :steward,
    roles: [
      foley: [
        eleven_labs_api_key: key,
        jobs: [
          effects: [api_key: key],
          vamp: [api_key: key]
        ]
      ]
    ]
end

if key = System.get_env("HUME_API_KEY") do
  config :thereish, :steward, roles: [foley: [hume_api_key: key]]
end

if key = System.get_env("HUME_SECRET_KEY") do
  config :thereish, :steward, roles: [foley: [hume_secret_key: key]]
end

# Music keys are vendor-scoped on the role, so whichever provider the music job
# names finds its own key (`Thereish.Steward.provider/3`).
if key = System.get_env("MUREKA_API_KEY") do
  config :thereish, :steward, roles: [foley: [mureka_api_key: key]]
end

if key = System.get_env("APIFRAME_API_KEY") do
  config :thereish, :steward, roles: [foley: [apiframe_api_key: key]]
end

if key =
     System.get_env("RECRAFT_API_TOKEN") || System.get_env("RECRAFT_API_KEY") ||
       System.get_env("RECRAFT_AI_API_KEY") do
  config :thereish, :steward, roles: [limner: [recraft_api_key: key]]
end

if key = System.get_env("IDEOGRAM_API_KEY") do
  config :thereish, :steward, roles: [limner: [ideogram_api_key: key]]
end

if key = System.get_env("BFL_API_KEY") || System.get_env("BLACK_FOREST_LABS_API_KEY") do
  config :thereish, :steward, roles: [limner: [bfl_api_key: key]]
end

if key = System.get_env("FAL_KEY") || System.get_env("FAL_AI_API_KEY") do
  config :thereish, :steward, roles: [limner: [fal_api_key: key]]
end

if script_url = System.get_env("UMAMI_SCRIPT_URL") do
  config :thereish, :umami, script_url: script_url
end

if website_id = System.get_env("UMAMI_WEBSITE_ID") do
  config :thereish, :umami, website_id: website_id
end

if to = System.get_env("NOTICE_TO") do
  config :thereish, :notice, to: to
end

if from = System.get_env("NOTICE_FROM") do
  config :thereish, :notice, from: from
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :thereish, ThereishWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/thereish_web/router\.ex$"E,
        ~r"lib/thereish_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :thereish, Thereish.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :thereish, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :thereish, ThereishWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :thereish, ThereishWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :thereish, ThereishWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  aws_access_key_id = System.get_env("AWS_ACCESS_KEY_ID")
  aws_secret_access_key = System.get_env("AWS_SECRET_ACCESS_KEY")
  aws_region = System.get_env("AWS_REGION") || "us-east-1"

  if aws_access_key_id && aws_secret_access_key do
    config :thereish, Thereish.Mailer,
      adapter: Swoosh.Adapters.AmazonSES,
      access_key: aws_access_key_id,
      secret: aws_secret_access_key,
      region: aws_region
  end
end
