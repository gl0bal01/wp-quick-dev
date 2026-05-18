# Contributing to WP Quick Dev

Thanks for your interest in improving WP Quick Dev.

## Reporting Issues

- Search existing issues first to avoid duplicates.
- Include: OS, Docker version, PHP version, exact command, full error output.
- For setup failures, run with `bash -x ./setup.sh project-name` and attach the trace.

## Pull Requests

1. Fork the repo and create a feature branch from `main`.
2. Keep changes focused — one logical change per PR.
3. Run the setup end-to-end before submitting:
   ```bash
   ./setup.sh test-project
   cd test-project
   make up && make install
   make health
   make clean FORCE=1
   ```
4. Run `shellcheck setup.sh` and address findings where reasonable.
5. Validate the generated docker-compose:
   ```bash
   cd test-project && docker compose config >/dev/null
   ```
6. Update `README.md` if your change affects user-visible behavior.
7. Write commits in present tense, imperative mood (e.g. `Fix mailpit profile activation`).

## Coding Standards

- Bash: `set -euo pipefail` at top of every script.
- Quoted heredocs (`<< 'EOF'`) for generated config to prevent unintended expansion.
- Unquoted heredocs only when variable substitution is intended.
- No secrets in committed files; `.env.example` must contain placeholders only.
- Permissions: prefer `0775`/`0664` over `0777` outside of last-resort fixes.

## Scope

WP Quick Dev is a development-only tool. PRs adding production-hardening features
(TLS, secret managers, multi-host orchestration) are out of scope. Keep the tool
small and fast.

## License

By contributing, you agree your contributions are licensed under the MIT License
(see `LICENSE`).
