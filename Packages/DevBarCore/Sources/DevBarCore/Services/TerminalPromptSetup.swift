import Foundation

enum TerminalPromptSetup {
    static let command = """
    setopt PROMPT_SUBST 2>/dev/null
    export PS1='$(p="$PWD"; if [ "$p" = "$HOME" ]; then printf "# "; else printf "%s# " "$p"; fi)'
    export PROMPT='$(p="$PWD"; if [ "$p" = "$HOME" ]; then printf "# "; else printf "%s# " "$p"; fi)'
    printf '\\033[H\\033[2J'

    """
}
