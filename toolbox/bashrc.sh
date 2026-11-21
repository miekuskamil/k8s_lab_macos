# Shell settings for the toolbox: the kubectl shortcuts the course uses, and completion.
[ -n "${BASH_VERSION:-}" ] || return 0
case $- in *i*) ;; *) return 0 ;; esac
[ -n "${LAB_BASHRC_DONE:-}" ] && return 0
LAB_BASHRC_DONE=1
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
alias k=kubectl
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
alias kube-sync=/usr/local/lib/lab/kube-sync.sh
PS1='\[\e[36m\](lab)\[\e[0m\] \w \$ '
