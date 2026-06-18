# Security

Report security issues privately to the repository owner instead of opening a public issue.

## Secret Scanning

This repo enforces secret scanning in two places:

- Local hooks: `npm run hooks:install` installs a pre-commit hook that runs staged `gitleaks`.
- CI: `.github/workflows/security-gitleaks.yml` runs gitleaks on pull requests and pushes to `main`.

Run a full local scan with:

```bash
npm run security:gitleaks
```

Run the staged-only scan with:

```bash
npm run security:gitleaks:staged
```

The scan is configured by `.gitleaks.toml`. Only deterministic fixtures and generated output should be allowlisted; real secrets, provider keys, OAuth tokens, private keys, `.env` files, and machine-local credentials must not be committed.

## Compiler And Porting Boundaries

OpenCodeHX will exercise provider auth, tool execution, shell access, config loading, and generated TypeScript. Treat those surfaces as security-sensitive:

- Keep credentials at runtime boundaries and fixtures credential-free by default.
- Prefer typed externs/facades over broad `Dynamic` for security-relevant APIs.
- Do not encode personal paths, tokens, or provider keys in `genes-ts` repros.
- Keep generated artifacts reproducible and reviewable before considering any public release.

