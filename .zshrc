#!/usr/bin/env zsh
# ~/.zshrc tailored for: Arch Linux + tmux + LazyVim (Neovim) + PHP dev
#
# Install: cp this file to ~/.zshrc, then open a new terminal.
# First launch will auto-bootstrap the zinit plugin manager (needs internet + git).

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY       # store timestamps
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE      # commands starting with a space aren't recorded
setopt HIST_VERIFY
setopt SHARE_HISTORY          # share history live across tmux panes/windows
setopt INC_APPEND_HISTORY     # write immediately, not just on shell exit

# ---------------------------------------------------------------------------
# Core shell options
# ---------------------------------------------------------------------------
setopt AUTO_CD                # `foo` instead of `cd foo`
setopt AUTO_PUSHD             # cd pushes onto the dir stack
setopt PUSHD_IGNORE_DUPS
setopt EXTENDED_GLOB          # (.) files only, (/) dirs only, (om[1]) newest, etc.
setopt GLOB_DOTS              # globs match dotfiles too
setopt CORRECT                # mild command-name spelling correction
setopt INTERACTIVE_COMMENTS   # allow `#comment` at an interactive prompt

# ---------------------------------------------------------------------------
# Plugin manager: zinit (fast, lazy-loading, no framework bloat)
# ---------------------------------------------------------------------------
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Suggestions from history as you type (accept with -> or Ctrl-F)
zinit light zsh-users/zsh-autosuggestions

# Command turns green/red as valid/invalid before you hit enter
# (load last, as its docs recommend)
zinit light zsh-users/zsh-syntax-highlighting

# Up/down arrow cycles history filtered by what you've already typed.
# Provides the history-substring-search-up/down widgets bound below.
# Must load after zsh-syntax-highlighting (its docs recommend this order).
zinit light zsh-users/zsh-history-substring-search

# Extra completion definitions beyond what zsh ships with
zinit light zsh-users/zsh-completions

# fzf-powered tab completion menu (pairs well with fzf below)
zinit light Aloxaf/fzf-tab

# vi-mode with better mode indication + text objects, since you live in
# LazyVim already
zinit light jeffreytse/zsh-vi-mode

# ---------------------------------------------------------------------------
# Completion system
# ---------------------------------------------------------------------------
autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump-$ZSH_VERSION"

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' group-name ''
# fzf-tab preview for cd
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always $realpath 2>/dev/null'

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
# Starship is a single static binary, config lives in ~/.config/starship.toml,
# and it composes well with tmux (git branch/status, exec time, exit code).
# Install: sudo pacman -S starship   (or: yay -S starship-bin)
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
else
    # fallback prompt if starship isn't installed yet
    PROMPT='%F{cyan}%n@%m%f %F{yellow}%~%f %F{red}$%f '
fi

# ---------------------------------------------------------------------------
# fzf: fuzzy history search (Ctrl-R) and file finder (Ctrl-T)
# ---------------------------------------------------------------------------
# Install: sudo pacman -S fzf
if command -v fzf &>/dev/null; then
    source /usr/share/fzf/key-bindings.zsh 2>/dev/null
    source /usr/share/fzf/completion.zsh 2>/dev/null
fi

# ---------------------------------------------------------------------------
# Editor / tools
# ---------------------------------------------------------------------------
export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="nvim"

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
alias vim="nvim"
alias vi="nvim"
alias ansible='nocorrect ansible'

# pacman/yay shortcuts
alias pacs="sudo pacman -S"
alias pacr="sudo pacman -Rns"
alias pacu="sudo pacman -Syu"
alias pacq="pacman -Qi"
alias pacorphans="pacman -Qtdq"
if command -v yay &>/dev/null; then
    alias yays="yay -S"
    alias yayu="yay -Syu"
fi

# ls -> eza if you have it, else coreutils ls with color
# Install: sudo pacman -S eza
if command -v eza &>/dev/null; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -l --icons --group-directories-first"
    alias la="eza -la --icons --group-directories-first"
    alias lt="eza --tree --icons --level=2"
else
    alias ls="ls --color=auto"
    alias ll="ls -lh"
    alias la="ls -lah"
fi

# git shortcuts
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git log --oneline --graph --decorate -20"
alias gd="git diff"

# tmux shortcuts
alias ta="tmux attach -t"
alias tl="tmux ls"
alias tn="tmux new -s"

# PHP / composer
export PATH="$HOME/.config/composer/vendor/bin:$PATH"
alias artisan="php artisan"
alias pu="composer update"
alias pi="composer install"

# ---------------------------------------------------------------------------
# tmux auto-attach (optional)
# ---------------------------------------------------------------------------
# Uncomment to auto-attach to a "main" session (or create one) whenever you
# open a plain terminal outside of tmux/an existing session.
# if [[ -z "$TMUX" && -o interactive ]]; then
#     tmux attach -t main || tmux new -s main
# fi

# ---------------------------------------------------------------------------
# Key bindings (in addition to zsh-vi-mode defaults)
# ---------------------------------------------------------------------------
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# zsh-vi-mode finishes its own setup on the first prompt (via a precmd hook),
# which runs after this whole file, and it unconditionally rebinds ^R to
# plain incremental search -- silently undoing fzf's Ctrl-R fuzzy-history
# binding from the fzf block above. Re-apply it here, in zsh-vi-mode's own
# post-init hook, so it takes effect last and actually sticks. If fzf isn't
# installed, zsh-vi-mode's own default (plain incremental search) is used.
function zvm_after_init() {
    if command -v fzf &>/dev/null; then
        source /usr/share/fzf/key-bindings.zsh 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
