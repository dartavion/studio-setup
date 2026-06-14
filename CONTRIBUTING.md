# Contributing

Thanks for contributing! A few ground rules to keep the project secure and easy to maintain.

1. Pre-commit hooks (required)
   - Install: pip install pre-commit
   - Enable hooks: pre-commit install
   - Run locally (optional): pre-commit run --all-files

2. Secret management
   - Never commit API keys, tokens, private keys, or other credentials.
   - Use environment variables, GitHub Actions secrets, or a secrets manager.
   - If detect-secrets flags a false positive, generate or update .secrets.baseline and commit that baseline so CI accepts the intentional exception.

3. Pull requests
   - Open PRs against the default branch and describe the purpose concisely.
   - Keep changes focused; one logical change per PR.
   - Add tests or a manual verification note for behavioral changes.

4. CI and security
   - This repo runs a secret-scan on push/PR. Fix findings or add them to .secrets.baseline after review.
   - The maintainers may request rotation of any exposed credentials.

5. Code style & docs
   - Update README or SECURITY.md for user-facing changes.
   - Add examples where helpful and keep docs up to date.

Thank you — contributions are welcome! If you have questions about process or security, open an issue and tag @dartavion.
