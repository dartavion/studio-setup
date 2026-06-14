# Security and secret-scanning

This repository includes automated secret-scanning to help avoid accidentally committing credentials or private keys. The checks are intentionally conservative — they will flag anything that looks like a secret so you can review and explicitly ignore false positives.

What was added
- A pre-commit configuration (.pre-commit-config.yaml) that runs detect-secrets locally before commits and also enables common hygiene hooks (trailing-whitespace, EOF fixer, YAML check).
- A GitHub Action (.github/workflows/secret-scan.yml) that runs detect-secrets on push and pull requests and fails the job when potential secrets are detected.

How to opt-in locally
1. Install pre-commit (pip):
   pip install pre-commit
2. Install the git hook in your clone:
   pre-commit install
3. Run the checks locally (optional):
   pre-commit run --all-files

How to handle findings
- If detect-secrets flags a true secret, rotate it immediately and remove the secret from the git history.
- For false positives, add an explicit ignore to a generated .secrets.baseline file using detect-secrets tooling, then commit the baseline so CI will accept the intentional exception.

Notes
- Do not commit actual API keys, tokens, private keys, or other credentials. Use environment variables (see dotfiles/zshrc.local.template and dotfiles/powershell/profile.local.template.ps1) or secret stores (GitHub Actions secrets, HashiCorp Vault, etc.).
- The action is a guardrail, not a replacement for careful secret-management practices.
