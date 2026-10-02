detect_node_ip() {
  local node_ip=""

  node_ip=$(
    ip -4 route get 1.1.1.1 2>/dev/null |
      awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  ) || true

  if [[ -z "${node_ip}" ]]; then
    node_ip=$(hostname -I 2>/dev/null | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i !~ /:/) {
          print $i
          exit
        }
      }
    }') || true
  fi

  if [[ -z "${node_ip}" ]]; then
    echo "[-] Error: Unable to determine the node IPv4 address." >&2
    return 1
  fi

  printf '%s\n' "${node_ip}"
}
