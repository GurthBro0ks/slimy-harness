# Slimy Chat — Agent Operating Manual

You are an autonomous coding agent working in the Slimy Chat self-hosted chat platform repo.

## Startup Sequence (do this EVERY session)

1. `pwd` — confirm you're in the repo root (`/home/slimy/slimy-chat`)
2. `git log --oneline -10` — see recent commits
3. `docker compose ps` — verify all services are running
4. Pick the highest-priority task
5. Only THEN begin work

## Repo Structure

- `compose.yml` — Docker Compose stack definition
- `Revolt.toml` — Revolt server configuration
- `Caddyfile` — Caddy reverse proxy config
- `livekit.yml` — LiveKit voice/video config
- `custom/` — Custom theme and branding assets
- `data/` — Persistent data (MongoDB, etc.)
- `migrations/` — Database migration scripts
- `pwa-assets/` — Progressive Web App assets
- `scripts/` — Utility scripts (update-caddy.sh, generate_config.sh)

## Truth Gate

A change is only "done" when:
1. `docker compose config` validates without errors
2. Config file syntax is valid (TOML, YAML)
3. `docker compose up -d` applies changes without errors
4. Chat platform is accessible at `https://chat.slimyai.xyz`

## Forbidden Zones (DO NOT TOUCH)

- `.env*` files
- `data/` — persistent runtime data, never modify directly
- SMTP credentials, RabbitMQ credentials in compose.yml
- `data/db/` — MongoDB data directory
- Registration invite codes (operational secret)

## Work Rules

- ONE task per session. Complete it or document where you stopped.
- Changes to `compose.yml` or `Revolt.toml` require `docker compose up -d` to apply.
- Always backup config before modifying: `cp Revolt.toml Revolt.toml.bak`
- Small, surgical commits (`feat:`, `fix:`, `refactor:`).
- This is a Docker stack — changes are config-driven, not code-driven.

## End-of-Session Checklist

1. `docker compose ps` shows all services healthy
2. Config changes applied and verified
3. `git add -A && git commit -m "<type>: <description>"`
4. Update `/home/slimy/claude-progress.md` with session summary

## Tech Stack Quick Reference

- Platform: Revolt (Stoat fork) via Docker Compose
- Database: MongoDB (container)
- Cache/Broker: Redis/KeyDB (container)
- Message Queue: RabbitMQ (container)
- Reverse Proxy: Caddy (TLS termination)
- Voice/Video: LiveKit
- URL: `https://chat.slimyai.xyz`
- Remote: `git@github.com:GurthBro0ks/slime.chat.git`
- Branch: `main`
