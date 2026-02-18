# Git worktree helper — save to ~/.config/fish/functions/wt.fish
function wt --description "Create a git worktree with .wtsetup config"
    set -l branch $argv[1]
    if test -z "$branch"
        echo "Usage: wt <branch>"
        return 1
    end

    set -l main (git worktree list --porcelain 2>/dev/null | head -1 | sed 's/worktree //')
    if test -z "$main"
        echo "Not inside a git repository."
        return 1
    end

    if not test -f "$main/.wtsetup"
        echo "No .wtsetup found in $main"
        echo "Run the /wt skill in Claude Code to generate one."
        return 1
    end

    set -l repo (basename "$main")
    set -l dir (dirname "$main")/"$repo-$branch"

    # Create worktree
    git worktree add "$dir" -b "$branch" 2>/dev/null
    or git worktree add "$dir" "$branch"
    or begin
        echo "Failed to create worktree."
        return 1
    end

    # Parse .wtsetup
    set -l copy
    set -l link
    set -l patch_keys
    set -l install_cmd ""
    set -l post_setup_cmd ""
    set -l in_copy 0
    set -l in_link 0
    set -l in_patch 0

    for line in (cat "$main/.wtsetup")
        set -l trimmed (string trim -- "$line")

        if string match -q 'copy=(*' -- "$trimmed"
            set in_copy 1; set in_link 0; set in_patch 0; continue
        else if string match -q 'link=(*' -- "$trimmed"
            set in_link 1; set in_copy 0; set in_patch 0; continue
        else if string match -q 'patch_keys=(*' -- "$trimmed"
            set in_patch 1; set in_copy 0; set in_link 0; continue
        else if string match -q ')' -- "$trimmed"
            set in_copy 0; set in_link 0; set in_patch 0; continue
        else if string match -qr '^install="(.*)"' -- "$trimmed"
            set install_cmd (string match -r '^install="(.*)"' -- "$trimmed")[2]
            continue
        else if string match -qr '^post_setup="(.*)"' -- "$trimmed"
            set post_setup_cmd (string match -r '^post_setup="(.*)"' -- "$trimmed")[2]
            continue
        end

        if string match -q '#*' -- "$trimmed"; or test -z "$trimmed"
            continue
        end

        set -l val (string trim --chars='"' -- "$trimmed")

        if test $in_copy -eq 1
            set -a copy "$val"
        else if test $in_link -eq 1
            set -a link "$val"
        else if test $in_patch -eq 1
            set -a patch_keys "$val"
        end
    end

    # Sanitize branch for use in suffixes
    set -l slug (string replace -a '/' '-' -- "$branch")
    set slug (string replace -ra '[^a-zA-Z0-9_-]' '_' -- "$slug")

    # Copy declared files
    for f in $copy
        if test -f "$main/$f"
            mkdir -p "$dir/"(dirname "$f")
            cp "$main/$f" "$dir/$f"
            echo "  copied $f"
        end
    end

    # Patch env keys
    for f in $copy
        test -f "$dir/$f"; or continue
        for key in $patch_keys
            if grep -q "^$key=" "$dir/$f" 2>/dev/null
                if test (uname) = "Darwin"
                    sed -i '' "s|^\\($key=.*\\)|\\1_$slug|" "$dir/$f"
                else
                    sed -i "s|^\\($key=.*\\)|\\1_$slug|" "$dir/$f"
                end
                echo "  patched $key in $f"
            end
        end
    end

    # Symlink shared resources
    for f in $link
        if test -e "$main/$f"
            mkdir -p "$dir/"(dirname "$f")
            ln -sfn "$main/$f" "$dir/$f"
            echo "  linked $f"
        end
    end

    # Run install command
    if test -n "$install_cmd"
        echo "Running: $install_cmd"
        (cd "$dir" && eval $install_cmd)
    end

    # Run post-setup verification (baseline tests)
    if test -n "$post_setup_cmd"
        echo ""
        echo "Verifying baseline..."
        if cd "$dir" && eval $post_setup_cmd
            echo "  baseline OK"
        else
            echo "  ⚠ baseline check failed — review before starting work"
        end
    end

    echo ""
    echo "Ready: $dir"
end
