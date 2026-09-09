# Isolated native title fallback probe; only a unique QA print request is intercepted.
if [ "$1" = "-p" ]; then
  for title_arg in "$@"; do
    case "$title_arg" in
      *FALLBACK-NATIVE-ACCEPTANCE-SEP08*)
        printf '%s\n' '<title/>'
        exit 0
        ;;
    esac
  done
fi
