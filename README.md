# Nightshift

**Fire-and-forget long jobs to an always-on machine while you sleep.**

Dispatch a long job from your laptop in the evening, close the lid, go to bed. The job runs on an *always-on* machine you own — a mini PC, an old tower, a Raspberry Pi, a NAS, any Linux box — inside a supervised Hermes gateway, and the finished artifacts land back on your laptop in the morning. Check status or rsync artifacts back whenever you want. No cloud worker, no third-party compute. You can configure as many always-on machines as you like and pick one per job with `--on`. 

```
 evening                    night                       morning
 ────────                   ─────                       ───────
 nightshift "…"   ──►    target's gateway runs     ──►  nightshift --watch
 run_id in hand          the job, laptop asleep          artifact lands back
 (tunnel closed          (launchd/systemd +              (rsync over SSH,
  seconds later)         caffeinate, LAN-only)          status + tests green)
```

## The problem

Every "run this overnight"-style agent workflow that goes through an interactive chat dies when the chat does.

## The fix

Don't bind the job's lifecycle to the laptop at all. The target machine runs a permanently supervised gateway. One SSH `-L` tunnel + one fire-and-forget POST is the entire dispatch path. The tunnel only needs to live for the HTTP round-trip:

Night:

```bash
$ nightshift "reindex the photo library; write the report to /srv/reports/reindex.md"
```

Morning:

```bash
$ nightshift --latest                                    # last dispatch, any target
$ nightshift --watch --file /srv/reports/reindex.md  # poll until it appears
$ nightshift --land /srv/reports                         # rsync it home (default dest)
```

## Prerequisites

- One always-on machine you own running a **Hermes gateway** — its runs
  API binds `127.0.0.1:8642` (loopback-only; the SSH tunnel is the front
  door).
- **Passwordless SSH** to it: an alias in `~/.ssh/config` using a dedicated
  key (e.g. `Host home`). The CLI runs `ssh` under `BatchMode` — any
  prompt would stall a dispatch.

## Install

    ./install.sh                  # dispatch side (your laptop)
    ./install.sh --push <host>    # server side on an always-on box (SSH alias)

Define targets in `~/.nightshift/.env` (`NIGHTSHIFT_TARGETS="home"`, with a
matching `<NAME>_HOST=<ssh-alias>`; dedicated key, the CLI runs under
`BatchMode`), then verify:

    nightshift --doctor           # SSH / gateway / key checks per target

## Usage

    nightshift "reindex music library; write the report to ~/reports/index.md"
    nightshift --on studio "transcribe everything in ~/inbox/audio"
    nightshift --status <run_id>              # or --latest
    nightshift --watch --file ~/reports/index.md   # block until it exists
    nightshift --land ~/reports/index.md     # rsync back to ~/.nightshift/landed/

## Advanced Usage 
### `supervise` — when one run isn't enough

One session maxes out at ~90 iterations, so a full product build needs several chained runs — and nobody is awake at 03:00 to chain them.`supervise` is the multi-phase work overnight:

```bash
# on the server (recommended — a laptop sleep can't stall the chain):
ssh home 'nightshift supervise phase1.md phase2.md phase3.md --stop 08:30'
```
