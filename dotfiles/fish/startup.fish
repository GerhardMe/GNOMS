if status is-interactive
    # Diable welcome msg:
    set -g fish_greeting

    # PATH scripts
    set -gx PATH $HOME/.local/bin $PATH

    # ----------------------------------------------------------------
    # ------------------ Git auto commit messages --------------------
    # ----------------------------------------------------------------

    function git
        set -l subcmd $argv[1]
        switch $subcmd
            case c
                # git c <msg>  → use <msg> as commit message
                # git c        → auto-commit with timestamp
                if test (count $argv) -gt 1
                    command git commit -m "$argv[2..-1]"
                else
                    command git commit -m (date '+%Y-%m-%d %H:%M:%S')
                end

            case lts
                set -l ts (date '+%Y-%m-%d %H:%M:%S')
                command git commit -m "lts: $ts"

            case p
                command git push

            case a
                set -l ts (date '+%Y-%m-%d %H:%M:%S')
                command git add .
                command git commit -m "lts: $ts"
                command git push

            case ac
                set -l ts (date '+%Y-%m-%d %H:%M:%S')
                command git add .
                if test (count $argv) -gt 1
                    command git commit -m "$argv[2..-1]"
                else
                    command git commit -m "lts: $ts"
                end
                command git push

            case '*'
                # any other git command, just pass through
                command git $argv
        end
    end

    # ----------------------------------------------------------------
    # ------------------------------ !! ------------------------------
    # ----------------------------------------------------------------

    function bind_bang
        switch (commandline -t)
            case "!"
                commandline -t $history[1]
                commandline -f repaint
            case "*"
                commandline -i !
        end
    end

    function bind_dollar
        switch (commandline -t)
            case "!"
                commandline -t ""
                commandline -f history-token-search-backward
            case "*"
                commandline -i '$'
        end
    end

    function fish_user_key_bindings
        bind ! bind_bang
        bind '$' bind_dollar
    end

    # ----------------------------------------------------------------
    # -------------------- Functions for idiots ----------------------
    # ----------------------------------------------------------------

    function month
        set -l cur (date +%m)

        printf "\e[38;5;27m01 January (31)";   test "$cur" = "01"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;27m02 February (28/29)"; test "$cur" = "02"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;40m03 March (31)";     test "$cur" = "03"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;40m04 April (30)";     test "$cur" = "04"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;40m05 May (31)";       test "$cur" = "05"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;226m06 June (30)";     test "$cur" = "06"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;226m07 July (31)";     test "$cur" = "07"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;226m08 August (31)";   test "$cur" = "08"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;208m09 September (30)"; test "$cur" = "09"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;208m10 October (31)";   test "$cur" = "10"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;208m11 November (30)";  test "$cur" = "11"; and printf " <--"; printf "\e[0m\n"
        printf "\e[38;5;27m12 December (31)";   test "$cur" = "12"; and printf " <--"; printf "\e[0m\n"
    end

    # ----------------------------------------------------------------
    # ----------------------------- Aliases --------------------------
    # ----------------------------------------------------------------

    function dev
        # Enter the project's devShell and keep it from being garbage
        # collected: --profile installs the shell into a profile under
        # ~/.cache/gnoms/shells, which nix registers as a GC root.
        # Refreshed on every run. Build output stays visible, so a slow
        # first build shows progress instead of looking like a hang.
        if not test -f flake.nix
            echo "dev: no flake.nix in $PWD" >&2
            return 1
        end
        set -l shells "$HOME/.cache/gnoms/shells"
        mkdir -p $shells
        # basename + short hash of the full path, so two projects with the
        # same directory name don't overwrite each other's root
        set -l name (basename $PWD)-(string sub -l 8 (echo -n $PWD | sha256sum))
        nix develop --profile $shells/$name --command fish $argv
        # Each changed shell adds a profile generation, and every generation
        # is its own GC root. Keep only the current one so old versions of
        # the shell don't stay pinned.
        nix profile wipe-history --profile $shells/$name

        # The profile only pins the shell's runtime closure. Evaluating the
        # flake needs its inputs (mostly a ~200 MB nixpkgs checkout) and
        # `nix develop` runs the shell with bashInteractive from that same
        # nixpkgs — neither is in the closure, so every garbage collection
        # dropped them and the next `dev` re-fetched ~350 MB. Pin those too,
        # next to the profile, so the reconfigure cleanup prunes them alike.
        #
        # `nix flake archive --json` lists the store path of the flake and of
        # every input, straight from the lock file. Drop the old input roots
        # first, so a bumped input doesn't leave its previous checkout pinned.
        set -l archive (nix flake archive --json 2>/dev/null)
        rm -f $shells/$name-input-* $shells/$name-bash
        set -l i 0
        for path in (echo $archive | jq -r '.. | objects | .path? // empty')
            set i (math $i + 1)
            nix-store --add-root $shells/$name-input-$i -r $path >/dev/null
        end
        # bashInteractive comes from the flake's own nixpkgs input when it has
        # one (that is what `nix develop` uses), otherwise from the registry.
        set -l nixpkgs (echo $archive | jq -r '.inputs.nixpkgs.path // empty')
        if test -n "$nixpkgs"
            nix build "$nixpkgs#bashInteractive" --out-link $shells/$name-bash 2>/dev/null
        else
            nix build nixpkgs#bashInteractive --out-link $shells/$name-bash 2>/dev/null
        end
    end

    # Reconfigure
    alias reload='reconfigure reload'
    alias rebuild='reconfigure rebuild'
    alias upgrade='reconfigure upgrade'
    alias update='reconfigure update'

    # Power
    alias hibernate='systemctl hibernate'

    # Fun
    alias minecraft='egpu prismlauncher'
    alias quarium='asciiquarium --transparent'

    # Misc
    alias try='nix-shell -p'
    alias man='batman'
    alias neofetch='fastfetch'
    alias fetch='fastfetch'

end
