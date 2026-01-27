# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Git PS1 requirement
source /usr/share/git/completion/git-prompt.sh

# Configure to your liking
export GIT_PS1_SHOWDIRTYSTATE=1        # * unstaged, + staged
export GIT_PS1_SHOWSTASHSTATE=1        # $ stashed
export GIT_PS1_SHOWUNTRACKEDFILES=1    # % untracked
export GIT_PS1_SHOWUPSTREAM="auto"     # <> ahead/behind
export GIT_PS1_DESCRIBE_STYLE="branch" # Prefer branch names

# Custom PS1 with git and changes arrow color: green for success, red for error
PS1='\[\033[38;5;8m\]┏╼[\[\033[38;5;2m\]\u\[\033[38;5;8m\]@\[\033[38;5;214m\]\h \[\033[1;38;5;13m\]\W\[\033[38;5;8m\]]\[\033[38;5;11m\]$(__git_ps1 " (%s)" 2>/dev/null)\n\[\033[38;5;8m\]┗┈┈╼\[$(if [[ $? == 0 ]]; then echo "\033[38;5;2m"; else echo "\033[38;5;1m"; fi)\]ᚧ \[\033[0m\]'

# Add blank line between command
[[ $- == *i* ]] && PROMPT_COMMAND='[[ $FIRST_PROMPT_DONE ]] && echo; FIRST_PROMPT_DONE=1'

[[ $PS1 && -f /usr/share/bash-completion/bash_completion ]] && \
    . /usr/share/bash-completion/bash_completion

export HISTCONTROL=ignoreboth
