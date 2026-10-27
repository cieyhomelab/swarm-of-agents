# swarm-of-agents

An autonomous software house running on [Cezar](https://github.com/open-mercato/cezar). The swarm proposes positive app ideas — ones that improve people's quality of life, finances or health. The owner's only step is to evaluate an idea with the model in the cezar-pwa phone app and approve or reject it. After approval, agents build and deploy the app privately on the owner's VPS with no human involvement.

Successor of [sh-skills](https://github.com/cieyhomelab/sh-skills) and runs side by side with it. Everything here uses the `sw` prefix, so nothing in sh-skills is overwritten.

- Spec (Polish): `.ai/specs/2026-10-25-autonomiczny-software-house.md`
- Architecture decision: `docs/adr/0001-stos-technologiczny.md`
- Working rules for agents: `AGENTS.md`
- Review rules: `CODE_REVIEW.md`

## How it works

This repository has no server and no database. Cezar is the engine. GitHub holds all state. This repository provides the logic:

| Part | Where | What it does |
|------|-------|--------------|
| Skills | `skills/sw-*/SKILL.md` | Instructions for each agent role (generator, analyst, architect, engineer, …) |
| Workflows | `workflows/sw-*.yml` | Cezar v2 workflows: `sw-sweep` (hourly cycle), `sw-ocena` (idea evaluation), `sw-spec` (specification), `sw-build` (build and deploy) |
| Scripts | `bin/sw-*` | Deterministic steps such as the gate, state changes, merge, repo creation, deploy and notifications |
| Config | `config/sw.json` | Limits, models, stage switch, deploy settings |

State lives in the private control repository `sw-control`. Each idea is an issue labelled `sw-pomysl`. Its state is a label: `sw-w-ocenie` → `sw-zatwierdzony` / `sw-odrzucony`, then `sw-stan-*` for the project. A `sw-dziennik` issue is the journal.

### The lifecycle of one app

1. **Cycle.** The Cezar automation `sw: przegląd co godzinę` runs `sw-sweep` in `sw-control`. `bin/sw-gate` decides what to do. At most one project is active at a time.
2. **Idea (S1).** When nothing is active, `sw-generator` invents an idea and checks it on the web. It rejects excluded categories (`config/kategorie-wykluczone.md`), ideas that free tools already cover, ideas without sources and duplicates. A good idea becomes an issue with an idea card, and you get a push notification.
3. **Evaluation (S2, S3) — your only step.** Open the notification in cezar-pwa. Talk with `sw-analityk` about the idea. It shows a summary and two buttons, **Zatwierdź** (approve) and **Odrzuć** (reject). If you reject, the next cycle generates a new idea and uses your reason as a hint.
4. **Repository and spec (S4).** The swarm creates a private repo named after the idea. The analyst writes the spec. An independent reviewer and a security review check it, and the spec PR is merged automatically.
5. **Build (S5–S9, stage 2 and 3).** The architect picks a stack and splits the app into modules with contracts. It adds a skeleton and CI. Engineers implement the modules, with up to `maxParallelAgents` agents working at once. The integrator assembles the modules. The tester runs E2E tests, and a security review checks the whole app. Each PR is merged only when a reviewer on another model approved it, CI is green and the security review passed.
6. **Deploy (S10).** `bin/sw-deploy` runs the app in Docker on an internal network. The only way in is an nginx proxy with basic auth on `deploy.bindAddress`. You get a notification with the address.
7. **Pause (S11, S12).** If a project uses up its retries, fix rounds, time limit or usage limit, `bin/sw-pause` pauses it, closes the issue and notifies you. The next cycle starts a new idea. Paused projects are not resumed automatically.

### Stages

`stage` in `config/sw.json` sets how far the swarm goes:

- **`1`** (default) — the swarm stops at the merged spec. It hands the project to the existing sh-* chain (`bin/sw-handover-sh`), and that chain keeps its human gates.
- **`2`** — the swarm builds the app with one module, deploys it and notifies you, all without a human.
- **`2` + `"multiModule": true`** — stage 3: several modules built in parallel, then integrated. Turn this on only after the parallel module tasks are wired into `sw-build` (see `AGENTS.md`, "Przydział modułów").

## Requirements

On the VPS:

- Cezar running (default `http://127.0.0.1:4321`), with cezar-pwa and the `cezar-push` sidecar (`http://127.0.0.1:4330`, token in `~/.cezar-push/gate-token`).
- Claude Code logged in on a **Claude Max** plan. `ANTHROPIC_API_KEY` and other API or cloud-provider variables must not be set. `sw-doctor` checks this. Also turn off paid extra usage ("usage credits") in your Claude account settings. No script can check that setting.
- `gh` logged in as the owner account (`githubOwner` in `config/sw.json`).
- `bash`, `git`, `jq`, `curl`, `python3`. Stage 2 and later also need `docker`.

## Setup on the VPS

1. **Clone and install the skills.**

   ```bash
   git clone https://github.com/cieyhomelab/swarm-of-agents ~/swarm-of-agents
   ~/swarm-of-agents/scripts/install.sh   # links skills/sw-* into ~/.claude/skills
   ```

   `install.sh` creates or replaces only `sw-*` symlinks. It leaves `sh-*` skills alone. Use `--dry-run` to see what it would do.

2. **Review the config.** Edit `~/swarm-of-agents/config/sw.json`. At minimum, check `githubOwner`, `controlRepo` (must be named `sw-*`) and `stage`. All fields are listed in `AGENTS.md`, section "Konfiguracja `config/sw.json`". Optional environment variables are in `.env.example`.

3. **Create the control repository and the hourly automation.** Run the `sw-start` skill as a Cezar task, or run the script directly with `CEZ_BIN` pointing to Cezar's `cez` binary:

   ```bash
   CEZ_BIN=/path/to/cez ~/swarm-of-agents/bin/sw-start
   ```

   It creates the private `sw-control` repo and registers it as a Cezar project if it is missing. It adds the `sw-*` labels, copies `sw-sweep` and `sw-ocena` into `.ai/cezar/workflows/`, opens the `sw-dziennik` issue and creates the `sw: przegląd co godzinę` automation, enabled. You can safely run it again: it only adds or updates what differs, and it never deletes automations. The last line is `STAN: OK` or `STAN: BLAD <reason>`.

4. **Let evaluations wait for you.** Cezar closes a session that waits for an answer after `resources.idleTimeoutMinutes` (15 by default). An idea evaluation would then end without your decision. Turn the limit off (it applies to the whole Cezar; waiting tasks hold no slot):

   ```bash
   curl -s -X PUT http://127.0.0.1:4321/api/v1/workspace/config -H 'Content-Type: application/json' \
     -d '{"resources":{"idleTimeoutMinutes":0}}'
   ```

5. **Check health.**

   ```bash
   ~/swarm-of-agents/bin/sw-doctor        # STAN: OK
   ```

6. **Stage 2 only: set the deploy login.** Deployed apps are protected with your login. The deploy fails (`STAN: BLAD`) without this file:

   ```bash
   mkdir -p ~/.sw-deploy
   printf 'login:password\n' > ~/.sw-deploy/owner-login
   chmod 600 ~/.sw-deploy/owner-login
   ```

   Set `deploy.bindAddress` to a specific private IPv4 of the VPS, never `0.0.0.0`.

7. **First run.** Wait for the next hourly cycle, or run the `sw-sweep` workflow by hand in the `sw-control` project in Cezar. When an idea is ready, a notification arrives on your phone.

## Day to day

- **Approve or reject ideas** in cezar-pwa when a notification arrives. That is the only input the swarm needs.
- **Follow progress** in `sw-control`: the labels on the idea issue show the state, and the `sw-dziennik` issue logs each event. App repos are tagged with the GitHub topic `sw-projekt`.
- **Notifications** you can get: new idea, spec ready (stage 1), app deployed (with address), project paused (with reason), and blocked (no idea or a broken environment for `noIdeaNotifyAfterCycles` cycles in a row). From stage 2, deployed and paused notifications also show the share of projects finished without intervention, for example ` · 67% bez interwencji`.
- **Change limits** in `config/sw.json`, for example `maxParallelAgents`, `projectTimeLimitHours`, `projectUsageLimitUsd` or `models.*`. Scripts read the file on every run. After changing `cycleHours` or the workflows, run `sw-start` again to update the automation and the workflow copies.

## Updating

```bash
git -C ~/swarm-of-agents pull
~/swarm-of-agents/scripts/install.sh
CEZ_BIN=/path/to/cez ~/swarm-of-agents/bin/sw-start   # when workflows or cycleHours changed
~/swarm-of-agents/bin/sw-doctor
```

After an update, the `sh-*` entries in `~/.claude/skills` must be unchanged.

## Development

You need `bash`, `bats`, `shellcheck`, `jq`, `python3` with PyYAML, and `docker` with Compose. Nothing needs to be installed with npm or pip.

```bash
scripts/lint.sh                      # shellcheck, workflow validation, sw naming rule, JSON
scripts/test-unit.sh [file]          # bats tests/unit
scripts/test-integration.sh [file]   # bats tests/integration (filesystem, HTTP to the mock)
scripts/test-e2e.sh [file]           # Docker Compose: mock API + a VPS-like container
scripts/build.sh                     # dist/swarm-of-agents.tar.gz
```

Tests never call the real GitHub, Cezar or models. They use fakes (`tests/fakes/`, `tests/tools/mock_api.py`). Conventions for naming, scripts, state, secrets and tests are in `AGENTS.md`.

## License

See `LICENSE`.
