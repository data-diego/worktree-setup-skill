# wt — Git Worktree Setup Skill

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that generates a `.wtsetup` config for your project and installs a `wt` shell function, so spinning up a new worktree is one command with env files, shared services, and dependencies handled automatically.

## Install

```bash
npx skills add data-diego/worktree-setup-skill --skill wt
```

## Update

```bash
npx skills update data-diego/worktree-setup-skill
```

## Usage

In Claude Code, run `/wt` in any git repo. The skill will:

1. **Analyze your project** — finds env files, secrets, Docker volumes, lockfiles, and test commands
2. **Generate `.wtsetup`** — a config file at your repo root
3. **Install the `wt` shell function** — into your `~/.zshrc`, `~/.bashrc`, or fish config

Then from your terminal:

```bash
wt my-feature
# Creates ~/code/myrepo-my-feature with everything set up
```

## What `.wtsetup` looks like

```bash
copy=(                    # Files copied to each new worktree
  ".env.local"
  "config/master.key"
)
link=(                    # Symlinked (shared across worktrees, e.g. Docker volumes)
  "pgdata"
)
patch_keys=(              # Env keys that get branch suffix to avoid conflicts
  "DATABASE_URL"          # e.g. myapp_dev → myapp_dev_my-feature
  "DB_NAME"
)
install="bundle install"
post_setup="bundle exec rspec"  # Baseline test verification
```

## Features

- **Env file copying** — `.env*`, `master.key`, `credentials.yml.enc`, `.secret*`
- **Env patching** — appends branch slug to DB names, ports, Redis URLs to avoid conflicts between worktrees
- **Shared service linking** — symlinks Docker volumes instead of duplicating them
- **Dependency install** — auto-detects bundler, pnpm, npm, yarn, bun, pip, poetry, go, cargo, mix, composer
- **Baseline tests** — runs your test suite after setup to verify a clean state
- **Shell support** — bash, zsh, and fish
- **Cross-platform** — macOS and Linux (`sed -i` handled for both)

## Supported stacks

Ruby/Rails, Node.js, Python, Go, Rust, Elixir, PHP — detected from lockfiles.
