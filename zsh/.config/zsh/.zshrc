for f in "$ZDOTDIR"/rc.d/*.zsh(N); do
  [[ -r "$f" ]] && source "$f"
done
unset f

# opencode
export PATH=/home/j4kuuu/.opencode/bin:$PATH
