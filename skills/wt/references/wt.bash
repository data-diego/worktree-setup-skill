# Git worktree helper — add to ~/.zshrc or ~/.bashrc
wt() {
  local branch="$1"
  [ -z "$branch" ] && echo "Usage: wt <branch>" && return 1

  local main
  main=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/worktree //')
  [ -z "$main" ] && echo "Not inside a git repository." && return 1

  if [ ! -f "$main/.wtsetup" ]; then
    echo "No .wtsetup found in $main"
    echo "Run the /wt skill in Claude Code to generate one."
    return 1
  fi

  local repo
  repo=$(basename "$main")
  local dir="$(dirname "$main")/${repo}-${branch}"

  # Create worktree (try new branch first, fall back to existing)
  git worktree add "$dir" -b "$branch" 2>/dev/null \
    || git worktree add "$dir" "$branch" \
    || { echo "Failed to create worktree."; return 1; }

  # Load project config
  local copy=()
  local link=()
  local patch_keys=()
  local install=""
  local post_setup=""
  source "$main/.wtsetup"

  # Sanitize branch for use in DB names, ports, etc.
  local slug="${branch//\//-}"
  slug="${slug//[^a-zA-Z0-9_-]/_}"

  # Copy declared files
  for f in "${copy[@]}"; do
    if [ -f "$main/$f" ]; then
      mkdir -p "$dir/$(dirname "$f")"
      cp "$main/$f" "$dir/$f"
      echo "  copied $f"
    fi
  done

  # Patch env keys to avoid conflicts between worktrees
  if [ ${#patch_keys[@]} -gt 0 ]; then
    for f in "${copy[@]}"; do
      [ ! -f "$dir/$f" ] && continue
      for key in "${patch_keys[@]}"; do
        if grep -q "^${key}=" "$dir/$f" 2>/dev/null; then
          if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^\(${key}=.*\)|\1_${slug}|" "$dir/$f"
          else
            sed -i "s|^\(${key}=.*\)|\1_${slug}|" "$dir/$f"
          fi
          echo "  patched $key in $f"
        fi
      done
    done
  fi

  # Symlink shared resources
  for f in "${link[@]}"; do
    if [ -e "$main/$f" ]; then
      mkdir -p "$dir/$(dirname "$f")"
      ln -sfn "$main/$f" "$dir/$f"
      echo "  linked $f"
    fi
  done

  # Run install command
  if [ -n "$install" ]; then
    echo "Running: $install"
    (cd "$dir" && eval "$install")
  fi

  # Run post-setup verification (baseline tests)
  if [ -n "$post_setup" ]; then
    echo ""
    echo "Verifying baseline..."
    if (cd "$dir" && eval "$post_setup"); then
      echo "  baseline OK"
    else
      echo "  ⚠ baseline check failed — review before starting work"
    fi
  fi

  echo ""
  echo "Ready: $dir"
}
