# Secret Santa — Feature Specification

A small Elixir/Phoenix web app for running Secret Santa gift exchanges. It is
run by a single organizer on their own machine, once a year or so. There is no
authentication: whoever can reach `localhost` is the organizer. Participants
never interact with the app; they only receive an email telling them who they
drew.

## 1. Goals and non-goals

**Goals**

- Create a gift exchange and add participants (name + email).
- Express one-directional exclusions ("Alice must not draw Bob").
- Produce a valid random assignment that honors the exclusions.
- Email each participant the name of the person they drew.
- Resend any participant's email later, e.g. after restarting the app weeks
  later because someone lost theirs.

**Non-goals**

- User accounts, logins, or any multi-user access control.
- Participant-facing pages (wishlists, RSVP, magic links).
- Hosting on the public internet.
- Editing or redrawing an exchange after it has been drawn (see §4.4).

## 2. Technical baseline

| Concern       | Choice                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| Framework     | Phoenix 1.8, LiveView for all pages                                    |
| Database      | SQLite via `ecto_sqlite3`; single file on disk, trivially backed up    |
| Email         | Swoosh. SMTP adapter in prod, Local adapter (`/dev/mailbox`) in dev    |
| Configuration | SMTP settings from environment variables only; nothing secret in the DB|
| Auth          | None. The app binds to `127.0.0.1` by default                          |

### 2.1 SMTP configuration

All of the following are read at boot from the environment (a `.env` file
loaded by the user's shell is fine):

| Variable        | Purpose                                            |
| --------------- | -------------------------------------------------- |
| `SMTP_HOST`     | e.g. `127.0.0.1` for Proton Bridge                 |
| `SMTP_PORT`     | e.g. `1025`                                        |
| `SMTP_USERNAME` |                                                    |
| `SMTP_PASSWORD` |                                                    |
| `SMTP_FROM`     | From address on every outgoing email               |
| `SMTP_TLS`      | `always` / `if_available` / `never` (default `if_available`) |
| `SMTP_TLS_VERIFY` | `peer` / `none` (default `peer`). Proton Bridge presents a self-signed certificate, so it needs `none`. |

Proton Mail note: Proton has no public SMTP endpoint. The organizer runs
[Proton Bridge](https://proton.me/mail/bridge) locally, which exposes a plain
SMTP server on `localhost`; the variables above point at it. Nothing in the app
is Proton-specific.

In `MIX_ENV=dev` the Local adapter is used unconditionally, so no email can
leave the machine while developing. Real sending only happens under prod
config.

## 3. Data model

### Exchange

| Field       | Notes                                              |
| ----------- | -------------------------------------------------- |
| `name`      | Required. e.g. "Family 2026".                      |
| `drawn_at`  | `nil` until the draw is made; set once, never cleared |

An exchange is **open** while `drawn_at` is `nil` and **drawn** afterwards.

### Participant

| Field           | Notes                                                        |
| --------------- | ------------------------------------------------------------ |
| `exchange_id`   |                                                              |
| `name`          | Required. Unique within the exchange.                        |
| `email`         | Required. Basic format check. Unique within the exchange.    |
| `recipient_id`  | The participant they drew. `nil` until drawn.                |
| `last_sent_at`  | Timestamp of the last successful email, or `nil`.            |
| `last_error`    | Message from the last failed send attempt, or `nil`. Cleared on success. |

### Exclusion

| Field            | Notes                                                    |
| ---------------- | -------------------------------------------------------- |
| `exchange_id`    |                                                          |
| `giver_id`       | The participant who is constrained                       |
| `excluded_id`    | The participant `giver` must not draw                    |

Exclusions are **one-directional**. "Alice must not draw Bob" says nothing
about whether Bob may draw Alice; the organizer adds the reverse explicitly if
wanted. `(giver_id, excluded_id)` is unique. A participant can never draw
themselves; that rule is implicit and not stored.

## 4. Features

### 4.1 Exchange list (home page)

- Lists every exchange, newest first, with its name, participant count, and
  status (open / drawn on `<date>`).
- "New exchange" creates an empty open exchange from a name.
- "New from previous" (per row) creates a new open exchange, prompting for a
  name, and copies that exchange's participants and exclusions into it. No
  assignments or send history are copied.
- "Delete" (per row, with confirmation) removes the exchange and everything
  under it. Allowed in either state.

### 4.2 Managing participants (open exchanges only)

- Add a participant by name and email; edit or remove existing ones.
- Validation, all enforced on save and surfaced inline:
  - name and email are required;
  - email passes a basic format check;
  - name is unique within the exchange;
  - email is unique within the exchange.
- Removing a participant also removes every exclusion that references them.

### 4.3 Managing exclusions (open exchanges only)

- For each participant, the organizer can tick any other participants that
  they must **not** draw. This is a block-list: anyone unticked is allowed.
- Changes save immediately (LiveView), no separate submit step.
- **Live validation.** As soon as any participant has zero legal recipients
  (everyone else is excluded), the UI flags that participant with a warning
  and the Draw button is disabled with an explanation. The organizer never
  has to click Draw to find out the constraints are unsatisfiable in the
  obvious way. (Non-obvious infeasibility, e.g. two people who can only draw
  the same third person, is still caught at draw time; see 4.4.)

### 4.4 Drawing

- The Draw button is enabled only when:
  - the exchange is open;
  - there are at least **3** participants;
  - live validation reports no participant with zero legal recipients.
- Drawing finds a random assignment where each participant gives to exactly
  one other and receives from exactly one other, honoring every exclusion.
  Small cycles (Alice ↔ Bob) are permitted; there is no single-cycle
  requirement.
- Drawing is confirmed with a dialog because it is irreversible.
- On success, every participant's `recipient_id` is set and `drawn_at` is
  stamped, in one transaction.
- If no valid assignment exists, nothing is written and the UI shows an error
  naming the participants involved where it can.
- **Once drawn, an exchange is immutable.** Participants and exclusions
  become read-only and there is no redraw. To change anything, the organizer
  creates a new exchange (usually via "New from previous") and draws again.
  The only actions left on a drawn exchange are revealing, sending, and
  deleting.

### 4.5 Viewing assignments (drawn exchanges)

- The participant table shows each giver with their recipient **masked** by
  default, so the organizer does not accidentally spoil their own draw.
- Each row has a "Reveal" toggle that shows the recipient's name for that row
  only. Nothing is remembered between page loads; every visit starts masked.

### 4.6 Sending emails (drawn exchanges)

- Each email is plain text, addressed to one participant, from `SMTP_FROM`,
  and says in substance:

  > Hi Alice,
  >
  > For **Family 2026**, you drew: **Bob**.

  Nothing else is included: no budget, date, wishlist, or organizer note.

- **Send all** sends to every participant whose `last_sent_at` is `nil`. It
  therefore doubles as "retry everyone who failed" and never double-sends on
  a second click. Sending is sequential and synchronous; the table updates
  per row as each send succeeds or fails.
- **Resend** (per row) sends to that one participant unconditionally. This is
  the recovery path for "I lost my email", and works after the app has been
  shut down and started again at any later date.
- Every attempt updates the row: success sets `last_sent_at` and clears
  `last_error`; failure leaves `last_sent_at` alone and stores the error
  message in `last_error`. The table shows a status column derived from these
  (Not sent / Sent `<time>` / Failed: `<error>`).

## 5. Out of scope for the first version, but deliberately left open

These were considered and rejected for now. They are listed so a future change
knows it is reversing a decision rather than filling a gap.

- **Redraw / editing after draw.** Rejected in favor of immutability plus
  "New from previous". Keeps every drawn exchange an honest record of what was
  emailed.
- **Mutual exclusions.** One-directional was chosen for precision; a "make
  mutual" shortcut could be added on top without changing the data model.
- **Auto-excluding last year's recipient** when cloning. Easy to add later as
  an option on "New from previous", since the previous exchange's assignments
  are retained.
- **Extra exchange fields** (date, budget, notes) and **participant wishlists**.
  Not needed while the email carries only the recipient's name.
- **HTML email.** Plain text is sufficient and renders everywhere.
- **"Send test email" button.** The dev mailbox covers development; for prod,
  adding yourself as a participant is an adequate smoke test.
- **SMTP settings in the UI.** Would put a password on disk; env vars avoid it.
- **Async / background sending (Oban).** Group sizes are small enough that
  synchronous sends with per-row feedback are fine.
