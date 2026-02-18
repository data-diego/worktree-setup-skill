#!/usr/bin/env bash
# Analyze a git project and generate a .wtsetup file.
# Usage: analyze-project.sh [project-root]
set -euo pipefail

root="${1:-.}"
root="$(cd "$root" && pwd)"
output="$root/.wtsetup"

# --- Find files to copy (.env*, secrets) ---
envs=()
while IFS= read -r f; do
  envs+=("${f#./}")
done < <(cd "$root" && find . \( \
    -name ".env*" \
    -o -name "master.key" \
    -o -name "credentials.yml.enc" \
    -o -name ".secret*" \
  \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/.next/*" \
  -not -path "*/dist/*" \
  -not -path "*/vendor/*" \
  -not -path "*/tmp/*" \
  -not -path "*/__pycache__/*" \
  -not -path "*/.venv/*" \
  -not -path "*/venv/*" \
  -not -name ".env.example" \
  -not -name ".env.sample" \
  -not -name ".env.template" \
  | sort)

# --- Find dirs/files to symlink (shared across worktrees) ---
links=()

# Docker: detect volume mount paths from compose files
for dc in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
  if [ -f "$root/$dc" ]; then
    while IFS= read -r vol; do
      vol="${vol#./}"
      # Only suggest if the dir already exists (active volume)
      if [ -d "$root/$vol" ]; then
        links+=("$vol")
      fi
    done < <(grep -oP '^\s*-\s*\./?\K[^:]+' "$root/$dc" 2>/dev/null | sort -u || true)
    break
  fi
done

# --- Detect env keys that need patching per worktree ---
# Look for DATABASE_URL, REDIS_URL, PORT patterns in env files
patch_keys=()
for f in "${envs[@]}"; do
  if [ -f "$root/$f" ]; then
    while IFS= read -r key; do
      # Deduplicate
      local_found=0
      for existing in "${patch_keys[@]+"${patch_keys[@]}"}"; do
        [ "$existing" = "$key" ] && local_found=1 && break
      done
      [ "$local_found" -eq 0 ] && patch_keys+=("$key")
    done < <(grep -oP '^(DATABASE_URL|DB_NAME|DB_DATABASE|REDIS_URL|PORT|APP_PORT)(?==)' "$root/$f" 2>/dev/null || true)
  fi
done

# --- Detect package manager / dependency installer ---
install=""
if [ -f "$root/Gemfile.lock" ]; then
  install="bundle install"
elif [ -f "$root/pnpm-lock.yaml" ]; then
  install="pnpm install"
elif [ -f "$root/bun.lockb" ] || [ -f "$root/bun.lock" ]; then
  install="bun install"
elif [ -f "$root/yarn.lock" ]; then
  install="yarn install"
elif [ -f "$root/package-lock.json" ]; then
  install="npm install"
elif [ -f "$root/requirements.txt" ] || [ -f "$root/Pipfile.lock" ]; then
  install="pip install -r requirements.txt"
elif [ -f "$root/poetry.lock" ]; then
  install="poetry install"
elif [ -f "$root/go.sum" ]; then
  install="go mod download"
elif [ -f "$root/Cargo.lock" ]; then
  install="cargo fetch"
elif [ -f "$root/mix.lock" ]; then
  install="mix deps.get"
elif [ -f "$root/composer.lock" ]; then
  install="composer install"
fi

# --- Detect dev command ---
dev=""
if [ -f "$root/Procfile.dev" ]; then
  dev="foreman start -f Procfile.dev"
elif [ -x "$root/bin/dev" ]; then
  dev="bin/dev"
elif [ -f "$root/Procfile" ]; then
  dev="foreman start"
fi

# --- Write .wtsetup ---
{
  echo "# .wtsetup — worktree setup config"
  echo "# Sourced by the wt shell function when creating a new worktree."
  echo ""
  echo "# Files to copy from main worktree"
  echo "copy=("
  for f in "${envs[@]}"; do
    echo "  \"$f\""
  done
  echo ")"
  echo ""
  echo "# Files/dirs to symlink (shared across worktrees, e.g. Docker volumes)"
  echo "link=("
  for f in "${links[@]}"; do
    echo "  \"$f\""
  done
  echo ")"
  echo ""
  echo "# Env keys to patch per worktree (appends branch suffix to avoid conflicts)"
  echo "# e.g. DATABASE_URL=postgres://...myapp_db → myapp_db_<branch>"
  echo "patch_keys=("
  for k in "${patch_keys[@]+"${patch_keys[@]}"}"; do
    echo "  \"$k\""
  done
  echo ")"
  echo ""
  if [ -n "$install" ]; then
    echo "# Dependency install command"
    echo "install=\"$install\""
  else
    echo "# No lockfile detected — set manually"
    echo "# install=\"\""
  fi
  echo ""
  if [ -n "$dev" ]; then
    echo "# Dev command (informational — not run by wt)"
    echo "# dev=\"$dev\""
  fi
} > "$output"

echo "Created $output"
echo ""
cat "$output"
