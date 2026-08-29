#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# My Tweaks
alias ls='eza -l --icons'
alias la='eza -la --icons'
alias vim='nvim'

eval "$(starship init bash)"
