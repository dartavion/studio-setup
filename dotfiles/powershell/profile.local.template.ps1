## profile.local.ps1
##
## Machine-specific PowerShell config.
## Copy to the same folder as $PROFILE and rename to profile.local.ps1.
## This file is sourced at the end of profile.ps1 and is never committed.

## ── PATH additions ───────────────────────────────────────────────────────────

# $env:PATH = "C:\some\tool\bin;$env:PATH"

## ── secrets and tokens ───────────────────────────────────────────────────────

# $env:ANTHROPIC_API_KEY = "sk-ant-..."
# $env:GITHUB_TOKEN      = "ghp_..."
# $env:OPENAI_API_KEY    = "sk-..."

## ── cloud and infrastructure ─────────────────────────────────────────────────

# $env:GOOGLE_CLOUD_PROJECT  = "my-project-id"
# $env:GOOGLE_CLOUD_LOCATION = "us-central1"
# $env:AWS_PROFILE           = "my-profile"
# $env:AWS_DEFAULT_REGION    = "us-east-1"

## ── proxy (corporate networks) ───────────────────────────────────────────────

# $env:HTTP_PROXY  = "http://proxy.example.com:8080"
# $env:HTTPS_PROXY = "http://proxy.example.com:8080"
# $env:NO_PROXY    = "localhost,127.0.0.1,.internal"

## ── local aliases ────────────────────────────────────────────────────────────

# function work { Set-Location C:\Users\$env:USERNAME\Developer\my-company }
