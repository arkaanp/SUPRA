# Git Workflow Conventions

Use the same title shape for issues, branches, commits, and pull requests:

```text
type(scope): description
```

## Branching Workflow

`main` is the only permanent development branch. Work follows:

```text
issue / Kanban card -> feature branch from main -> pull request -> main
```

1. Create one GitHub issue and one matching Kanban task (Trello / project board) for each unit of work (1:1 correspondence).
2. Create a short-lived branch from the latest `main`, named with the issue scope, such as `feat/frontend-trip` or `fix/conditions`.
3. Keep one logical change per branch and pull request. A branch may change `mobile/`, `backend/`, `ml/`, and `docs/` together when the work requires an atomic contract change.
4. Open a PR into `main`, run the relevant checks (`python3 testing/scripts/run_checks.py` and/or `cargo test --locked`, `fvm flutter analyze`, `fvm flutter test`), and merge only when the issue scope is complete. Use a regular merge commit (`--no-ff` / `merge_method: merge`) so the complete feature-branch commit history is retained on `main`.
5. Mark the Kanban task done and delete the feature branch after the PR merges.

Never use squash merges or rebase merges for completed feature PRs. Squashing or rebasing rewrites the branch history and loses the individual commit record that documents how the work was developed. If a platform defaults to squash, override it explicitly with the regular merge method before merging.

The required work-tracking sequence is:

```text
GitHub issue + matching Kanban card -> feature branch -> pull request -> merge -> close issue and card
```

Before opening a PR, link it to the GitHub issue and Kanban task in the PR description using `Fixes #123`, `Closes #123`, or `Refs #123`. Add the branch name to the PR's development context when the GitHub UI supports it, and add a concise issue comment containing the PR link and branch name. Keep the GitHub issue, Kanban card, branch, and PR aligned to the same scope.

After merge, verify both the GitHub issue and Kanban card reflect the completed state. Do not close an issue before its linked PR has merged unless the issue is explicitly being closed as a duplicate or not planned.

Do not use long-lived frontend or API integration branches. Use feature flags or environment switches (such as `ALERTS_ENABLED`) when incomplete or opt-in behavior must merge safely.

Examples:

```text
feat(transit): add Transjakarta GTFS and Commute API planner
feat(frontend-home): wire 12-hour forecast card to ML endpoint
fix(api): prevent stale OpenAQ stations from overriding CAMS
fix(frontend-trip): preserve trip history across restarts
docs(docs): document architecture and Render deployment
test(testing): partition Rust unit and integration suites
feat(deployment): add Render Dockerfile and Blueprint config
```

## Types

Use the smallest accurate type:

| Type | Use for |
| --- | --- |
| `feat` | User-visible, API-visible, or deployment capability. |
| `fix` | Bug fix or incorrect behavior. |
| `docs` | Documentation-only change. |
| `test` | Test-only change or missing coverage. |
| `refactor` | Behavior-preserving code change. |
| `chore` | Tooling, cleanup, config, generated files, or maintenance. |
| `perf` | Performance-focused behavior change. |
| `hardening` | Reliability, security, observability, or operational safety. |
| `spike` | Time-boxed discovery with a written result. |
| `review` | Audit/review task that may not change code. |

## Scopes

Prefer concrete scopes that identify the affected SUPRA module or UI surface. If a change spans frontend and backend for one atomic feature, use the feature domain scope (`assistant`, `alerts`, `transit`, etc.) or split the work.

Recommended scopes:

```text
api
auth
conditions
transit
mobility
alerts
assistant
ml
commutes
frontend-auth
frontend-home
frontend-trip
frontend-assistant
frontend-alerts
frontend-profile
frontend-shell
testing
deployment
docs
repo
```

For frontend work, avoid bare `frontend` when a specific screen or surface is targeted. Name the product surface being changed (for example `frontend-home`, `frontend-trip`, `frontend-alerts`) so each commit is understandable without reading its diff.

For feature work, avoid bare `feat` unless the change truly spans the entire monorepo. Prefer:

```text
feat(conditions): ...
feat(frontend-trip): ...
feat(ml): ...
```

## Issues

Issue titles should describe the work, not a generic phase label.

Good:

```text
feat(assistant): pass selected Trip itinerary context to Gemini chat
fix(alerts): deduplicate ANTARA incident notifications per user
test(testing): add isolated PostgreSQL ownership smoke checks
```

Avoid:

```text
Sprint 3
Do later backend work
Frontend stuff
```

Issue descriptions should include:

- **Scope:** what belongs in this issue.
- **Out of scope:** nearby work that should not be included.
- **Done when:** concrete acceptance checks.
- **References:** docs, contracts, designs, or prior PRs that govern the work.

Template:

```md
## Scope
- ...

## Out of scope
- ...

## Done when
- ...

## References
- ...
```

## Commits

Each commit should describe one coherent change. Use bullet points in the commit body when the title alone is not enough.

Good commit title:

```text
fix(conditions): reject stale OpenAQ sensors older than 3 hours
fix(frontend-alerts): restore news severity selector on failed save
```

Optional commit body:

```text
- excludes inactive OpenAQ stations older than 24 hours from candidates
- falls back to Open-Meteo CAMS PM2.5/US AQI when no fresh station exists
- preserves stale labeling without altering original sensor timestamps
```

Avoid mixing unrelated work in one commit. If the commit needs "and" in the title across unrelated components, consider splitting it. Never commit secrets (`backend/.env`, `mobile/config/local.json`), build artifacts (`backend/target/`, `ml/artifacts/*.pt`), or large binary reports.

## Pull Requests

PR titles use the same format:

```text
feat(frontend-assistant): connect chat context pill to selected route
```

PR descriptions should include:

- **Summary:** bullet list of what changed.
- **Validation:** commands run and observed results.
- **Risks / notes:** migrations, env var changes, or limitations reviewers should watch.
- **Linked issues:** `Fixes #123`, `Closes #123`, or `Refs #123`.

Template:

```md
## Summary
- ...

## Validation
- `python3 testing/scripts/run_checks.py --stage unit`
- ...

## Risks / notes
- ...

Fixes #123
```

Use draft PRs for unfinished work. Mark ready only when the scope is complete, the working tree is clean, and the relevant checks have passed or any missing checks are explicitly explained.
