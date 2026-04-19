# the-elder-scrolls-speak

Auto-narrated audiobooks of in-game books from The Elder Scrolls universe, served as a Spotify-style web player.

- **Texts** scraped from [imperial-library.info](https://www.imperial-library.info/)
- **Metadata** cross-referenced from [UESP Lore:Books_by_Author](https://en.uesp.net/wiki/Lore:Books_by_Author)
- **Narration** generated once via AWS Polly long-form voices, streamed from S3
- **MVP scope:** Skyrim only

## Stack

AWS · Terraform · Python 3.12 (Lambda) · React + Vite · GitHub Actions (OIDC)

## Layout

```
infra/      Terraform (modules/, envs/dev/)
backend/    Python Lambdas (ingestion/, tts/, api/, shared/)
frontend/   React + Vite SPA
.github/    CI/CD workflows
```

## Implementation plan

See `/root/.claude/plans/i-want-to-create-sprightly-umbrella.md` (out of repo) — also summarised in commit history.

## Status

Phase 1 (infra skeleton) and code scaffolding for ingestion, TTS, API, and frontend in place. Not yet deployed.
