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
#     PHX_SERVER=true bin/secret_santa start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :secret_santa, SecretSantaWeb.Endpoint, server: true
end

config :secret_santa, SecretSantaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # Read `.env` from the project root so `MIX_ENV=prod mix phx.server` works
  # without first exporting anything from the shell. Dotenvy keeps the values
  # in its own store rather than the OS environment, so everything below
  # reads through `Dotenvy.env!/3`. Real environment variables are sourced
  # last and therefore win over the file; a missing `.env` is fine.
  Dotenvy.source!([".env", System.get_env()])

  env = fn name -> Dotenvy.env!(name, :string, nil) end

  database_path =
    env.("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/secret_santa/secret_santa.db
      """

  config :secret_santa, SecretSanta.Repo,
    database: database_path,
    pool_size: Dotenvy.env!("POOL_SIZE", :integer, 5)

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    env.("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = Dotenvy.env!("PHX_HOST", :string, "localhost")
  port = Dotenvy.env!("PORT", :integer, 4000)

  config :secret_santa, :dns_cluster_query, env.("DNS_CLUSTER_QUERY")

  # This app is only ever run on the organizer's own machine (spec.md §1,
  # §2), so even in prod it listens on loopback only and generates plain
  # http URLs. Anyone who can reach the port is the organizer; there is no
  # authentication to fall back on if it were exposed more widely.
  config :secret_santa, SecretSantaWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [ip: {127, 0, 0, 1}, port: port],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :secret_santa, SecretSantaWeb.Endpoint,
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
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :secret_santa, SecretSantaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Real email is only ever sent under prod config; dev uses the Local
  # adapter (see config/config.exs) and test uses the Test adapter. All
  # settings come from the environment so no credentials land on disk in
  # the database. See spec.md §2.1.
  smtp_env = fn name ->
    env.(name) ||
      raise """
      environment variable #{name} is missing.
      See spec.md §2.1 for the SMTP variables the app expects.
      """
  end

  smtp_tls =
    case Dotenvy.env!("SMTP_TLS", :string, "if_available") do
      "always" -> :always
      "if_available" -> :if_available
      "never" -> :never
      other -> raise "SMTP_TLS must be one of always, if_available, never; got #{inspect(other)}"
    end

  smtp_host = smtp_env.("SMTP_HOST")

  # `verify: :verify_peer` on its own is not enough: OTP ships no default
  # trust store, so ssl:connect refuses to start, and the STARTTLS upgrade
  # happens on an already-open socket so OTP does not know which hostname
  # to check against the certificate. Both have to be supplied explicitly
  # (see the "TLS options" section of Swoosh.Adapters.SMTP's docs).
  smtp_tls_options =
    case Dotenvy.env!("SMTP_TLS_VERIFY", :string, "peer") do
      "peer" ->
        [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(smtp_host),
          # OTP's default depth of 1 rejects chains with more than one
          # intermediate, which public providers such as Gmail send.
          depth: 5,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]

      "none" ->
        [verify: :verify_none]

      other ->
        raise "SMTP_TLS_VERIFY must be one of peer, none; got #{inspect(other)}"
    end

  config :secret_santa, SecretSanta.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(smtp_env.("SMTP_PORT")),
    username: smtp_env.("SMTP_USERNAME"),
    password: smtp_env.("SMTP_PASSWORD"),
    tls: smtp_tls,
    tls_options: smtp_tls_options,
    auth: :always,
    retries: 1

  config :secret_santa, :mail_from, smtp_env.("SMTP_FROM")
end
