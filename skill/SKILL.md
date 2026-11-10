---
name: nightshift
description: "Dispatch long/unattended agent jobs to an always-on home machine via its Hermes gateway; survives laptop sleep."
metadata:
  hermes:
    tags: [nightshift, remote-jobs, gateway, runs-api, homelab]
---

# Nightshift — dispatch jobs to an always-on machine

## When to use

- A job will outrun an interactive session: builds, reindexes, bulk
  transcription, migrations — anything that must keep running after the
  laptop sleeps or the app quits.
- A user says "run this overnight / on the server / while I'm away", or
  asks about a previously dispatched job ("is it done?").
- NOT for quick jobs that finish inside the current chat — just do them.

## Topology (what you control)

You (the agent) run on a machine that has SSH access to one or more
**targets** — always-on boxes configured in `~/.nightshift/.env`
(`NIGHTSHIFT_TARGETS="home office"`, default `NIGHTSHIFT_DEFAULT_TARGET`;
names are shell identifiers, their `_HOST` values are SSH aliases). Each
target runs a launchd/systemd-supervised Hermes gateway whose runs API binds
`127.0.0.1:8642`; the CLI reaches it through an SSH `-L` tunnel (one per
target, dedicated ports 18642+). Everything — config, CLI, run log, landed
artifacts — lives in the single root `~/.nightshift/`.

## Commands

```bash
nightshift --targets                       # who's available (run this first, once)
nightshift --doctor                        # health-check ALL targets (ssh/gateway/key)
nightshift "task text"                   # dispatch → default target
nightshift --on office "task text"       # dispatch → named target
nightshift --latest                      # status of most recent dispatch
nightshift --status <run_id>             # status (target auto-resolved)
nightshift --watch [--file PATH]         # block until done/artifact appears
nightshift --land <server-path> [dest]   # rsync finished work back (~/.nightshift/landed/)
nightshift supervise p1.md [p2.md …] [--stop HH:MM] [--interval SECS]
                                           # chain phases overnight, ON the server
```

`supervise` is for multi-phase work: one session ≈ 90 iterations max, so a
big build needs several chained runs and nobody is awake at 03:00 to chain
them. Run it on the server (`ssh home 'nightshift supervise …'`) so a
laptop sleep can't stall the chain: per phase it checks gateway health
(relaunches once if down), dispatches the phase file, polls to terminal,
saves the run JSON to `~/.nightshift/run-summaries/`. Always pass
`--stop HH:MM` — wall-clock discipline. Phase files must be self-contained
(verbatim paths, "read STATUS/ first", end with STATUS/<phase>.md totals).

## Rules (verified failure modes — follow them)

1. **One simple dispatch is the default.** Don't wire supervise/crons for
   a single job. Escalate to `supervise` (multi-phase chaining) only when
   the work genuinely has phases — and to a `--land` cron only when the
   user never wants to type `--land` again.
2. **Make every task prompt self-contained** and force a written artifact:
   state the working path verbatim and end the prompt with "write the full
   report to <path>". Run-status buffers are short-lived; files are the
   durable interface. The target's phase agent has NO memory of anything
   before its own run. **Write paths from the TARGET's perspective, never
   the laptop's** — homes/mounts differ per machine (a box whose home is
   `/Volumes/<volume>/<user>` has no `/Users/<user>` there; laptop paths hit
   root-owned dirs or nothing). Probe when unsure:
   `ssh <host> 'echo $HOME; ls /Volumes'`.
3. **The API `status` field is optimistic.** After a backend error the API
   keeps saying `running` while nothing is in flight. Ground truth = gateway
   log tail on the target + fresh artifact mtimes:
   `ssh <host> 'ls -l <artifact dir>'`. Answer "done?" from files, not
   status strings — even `completed` proves nothing until the artifact's
   actual content is seen (a run can complete having created nothing, e.g.
   it hit a permission wall and stopped politely).
4. **A `failed`/cap-cut run can still hold the complete deliverable** —
   pull the run output before treating failure as empty.
5. **Never dispatch through an interactive desktop-app chat** — it's
   tunnel-bound; the app dying SIGINTs the job (exit 130). `nightshift`
   exists precisely to bypass that.
6. **`hermes status` shows `Jobs: 0` while your run executes** — it counts
   cron jobs only. Don't conclude "nothing is running"; check
   `--status <run_id>` or the gateway log.
7. **Non-interactive PATH is minimal** on the targets (no `~/.local/bin`,
   brew may be shadowed). If a job needs rustup/brew tools, put the
   explicit `export PATH=...` inside the dispatched prompt.
8. **API key is read from the target's `.env` per call** (the CLI does
   this) — never cache or grep a local `.env`; machines have different keys.
9. **Wall-clock discipline:** anything that loops (supervisor, watcher)
   needs a hard stop time and must exit on terminal state — a watcher that
   keeps re-firing its notify pattern gets rate-suppressed to silence.
10. **macOS `rsync` is openrsync** (reports "rsync version 2.6.9
    compatible"): it rejects GNU-only flags like `--info=progress2`
    (usage error, easy to miss inside a wrapper). Use `--progress`;
    same rule inside dispatched prompts that run rsync on macOS targets.

## Typical flow

Morning handoff for the user: `nightshift --latest` or `--status <id>`;
artifacts via `--land`. If the user wants unattended delivery, offer a
morning `--land` cron entry. Before first dispatch of the day,
`nightshift --doctor` — green means ssh OK, `gateway: 404` (404 = UP,
loopback-bound; 000 = down).
