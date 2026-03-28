# hiterm zsh integration — sets up OSC 7 (CWD) and OSC 0 (title) hooks.
# Loaded via ZDOTDIR redirect; restores user's real ZDOTDIR first.

# Restore original ZDOTDIR so subsequent zsh config files load from the right place.
if [[ -n "$_HITERM_ZDOTDIR" ]]; then
    ZDOTDIR="$_HITERM_ZDOTDIR"
    unset _HITERM_ZDOTDIR
else
    unset ZDOTDIR
fi

# Source user's real .zshenv (if any).
[[ -f "${ZDOTDIR:-$HOME}/.zshenv" ]] && source "${ZDOTDIR:-$HOME}/.zshenv"

# Set up hooks for interactive shells only.
if [[ -o interactive ]]; then
    _hiterm_precmd() {
        # OSC 7: report working directory to libghostty (CWD inheritance).
        printf '\e]7;file://%s%s\a' "$HOST" "$PWD"
        # OSC 0: set tab title to current directory name.
        printf '\e]0;%s\a' "${PWD##*/}"
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _hiterm_precmd
fi
