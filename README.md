# SecretSanta

A small Phoenix app for running a Secret Santa gift exchange from your own
machine. You add participants, set who may not draw whom, make the draw, and
the app emails each person the name they drew. See [spec.md](spec.md) for the
full feature specification.

## Requirements

Versions are pinned in `.tool-versions` for [asdf](https://asdf-vm.com/):

- Erlang/OTP 28
- Elixir 1.18

## Development

```sh
mix setup        # deps, database, assets
mix phx.server   # http://localhost:4000
```

In development no email ever leaves the machine. Everything the app "sends"
is captured at <http://localhost:4000/dev/mailbox>.

Before committing, run `mix precommit` (compile with warnings as errors,
format check, unused-deps check, tests).

## Running for real

Real email is only sent under prod config. The app still binds to
`127.0.0.1` only; there is no authentication, so it must not be exposed
beyond the machine.

Set these environment variables (a `.env` file sourced by your shell works;
`.env` is gitignored):

| Variable          | Purpose                                                        |
| ----------------- | -------------------------------------------------------------- |
| `SECRET_KEY_BASE` | Generate once with `mix phx.gen.secret`                        |
| `DATABASE_PATH`   | Where the SQLite file lives, e.g. `~/.secret_santa/db.sqlite3` |
| `SMTP_HOST`       | SMTP server host                                               |
| `SMTP_PORT`       | SMTP server port                                               |
| `SMTP_USERNAME`   |                                                                |
| `SMTP_PASSWORD`   |                                                                |
| `SMTP_FROM`       | From address on every outgoing email                           |
| `SMTP_TLS`        | `always` / `if_available` / `never` (default `if_available`)   |
| `SMTP_TLS_VERIFY` | `peer` / `none` (default `peer`)                               |
| `PORT`            | Optional, default `4000`                                       |

Then:

```sh
MIX_ENV=prod mix setup
MIX_ENV=prod mix ecto.migrate
MIX_ENV=prod mix phx.server
```

### Proton Mail

Proton has no public SMTP endpoint. Run
[Proton Bridge](https://proton.me/mail/bridge) locally and point the app at
it. Bridge shows its host, port, username, and password in its settings;
it uses STARTTLS with a self-signed certificate, so:

```sh
SMTP_HOST=127.0.0.1
SMTP_PORT=1025
SMTP_TLS=always
SMTP_TLS_VERIFY=none
```
