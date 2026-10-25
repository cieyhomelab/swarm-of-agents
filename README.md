# swarm-of-agents

An autonomous software house running on [Cezar](https://github.com/open-mercato/cezar). The swarm proposes positive app ideas — ones that improve people's quality of life, finances or health. The owner's only step is to evaluate an idea with the model in the cezar-pwa phone app and approve or reject it. After approval, agents build and deploy the app privately on the owner's VPS with no human involvement.

Successor of [sh-skills](https://github.com/cieyhomelab/sh-skills) and runs side by side with it. Everything here uses the `sw` prefix, so nothing in sh-skills is overwritten.

- Spec (Polish): `.ai/specs/2026-10-25-autonomiczny-software-house.md`
- Architecture decision: `docs/adr/0001-stos-technologiczny.md`
- Working rules for agents: `AGENTS.md`

## Install on the VPS

```bash
git clone https://github.com/cieyhomelab/swarm-of-agents ~/swarm-of-agents
~/swarm-of-agents/scripts/install.sh   # links skills/sw-* into ~/.claude/skills
~/swarm-of-agents/bin/sw-doctor        # STAN: OK
```
