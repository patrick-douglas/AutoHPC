#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Erro: este script precisa ser executado como root."
  echo "Use:"
  echo "  sudo $0 $*"
  exit 1
fi

TARGET_IP="11.0.0.1"

HOSTS=(
  "stereo2"
  "mauro"
  "s5"
  "x99"
  "rock1"
  "rock2"
  "rock3"
  "rock4"
  "rock5"
  "rock6"
  "rock7"
)

MACS=(
  "e0:d5:5e:f3:a3:90"  # stereo2
  "04:42:1a:93:e6:79"  # mauro
  "a4:bf:01:37:22:ba"  # s5
  "60:45:cb:60:98:5f"  # x99
  ""  # rock1
  ""  # rock2
  ""  # rock3
  ""  # rock4
  ""  # rock5
  ""  # rock6
  ""  # rock7
)

SSH_OPTS=(
  -o ConnectTimeout=8
  -o BatchMode=no
)

usage() {
  cat <<EOF
Uso:
  $0 --on
  $0 --off
  $0 --reboot
  $0 --cmd "comando"
  $0 --help

Opções:
  --on              Liga máquinas via Wake-on-LAN
  --off             Desliga máquinas via SSH
  --reboot          Reinicia máquinas via SSH
  --cmd "comando"   Executa um comando em todos os nodes via SSH
  -h, --help        Mostra esta ajuda

Exemplos:
  $0 --cmd "hostname"
  $0 --cmd "systemctl restart slurmd"
  $0 --cmd "service slurm* restart"
EOF
}

get_wol_interface() {
  local iface=""

  iface=$(ifconfig | awk -v ip="$TARGET_IP" '
    /^[a-zA-Z0-9]/ {gsub(":", "", $1); current_if=$1}
    $0 ~ ip {print current_if; exit}
  ')

  if [[ -z "$iface" ]]; then
    echo "Erro: não encontrei interface com IP $TARGET_IP." >&2
    exit 1
  fi

  echo "$iface"
}

wake_cluster() {
  local iface
  iface="$(get_wol_interface)"

  echo "Usando interface: $iface (IP $TARGET_IP)"
  echo "Ligando cluster via Wake-on-LAN..."

  for i in "${!HOSTS[@]}"; do
    local host="${HOSTS[$i]}"
    local mac="${MACS[$i]}"

    if [[ -z "$mac" ]]; then
      echo "-> ${host}: MAC não definido, pulando..."
      continue
    fi

    echo "-> Ligando ${host} (${mac})"
    etherwake -D -b -i "$iface" "$mac"
    sleep 1
  done

  echo "Done."
}

shutdown_cluster() {
  echo "Desligando cluster via SSH..."

  for host in "${HOSTS[@]}"; do
    echo "-> Desligando ${host}"
    if ssh "${SSH_OPTS[@]}" "$host" "sudo poweroff"; then
      echo "   OK: ${host}"
    else
      echo "   ERRO: ${host}"
    fi
  done

  echo "Shutdown enviado."
}

reboot_cluster() {
  echo "Reiniciando cluster via SSH..."

  for host in "${HOSTS[@]}"; do
    echo "-> Reiniciando ${host}"
    if ssh "${SSH_OPTS[@]}" "$host" "sudo reboot"; then
      echo "   OK: ${host}"
    else
      echo "   ERRO: ${host}"
    fi
  done

  echo "Reboot enviado."
}

run_command_cluster() {
  local cmd="$1"

  echo "Executando comando em todos os nodes:"
  echo "  $cmd"
  echo

  local escaped_cmd
  escaped_cmd=$(printf '%q' "$cmd")

  for host in "${HOSTS[@]}"; do
    echo "============================================================"
    echo "NODE: ${host}"
    echo "============================================================"

    if ssh "${SSH_OPTS[@]}" "$host" "sudo bash -lc $escaped_cmd"; then
      echo
      echo "OK: ${host}"
    else
      echo
      echo "ERRO: ${host}"
    fi

    echo
  done

  echo "Comando finalizado em todos os nodes."
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

case "$1" in
  --on)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    wake_cluster
    ;;

  --off)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    shutdown_cluster
    ;;

  --reboot)
    if [[ $# -ne 1 ]]; then
      usage
      exit 1
    fi
    reboot_cluster
    ;;

  --cmd)
    if [[ $# -ne 2 ]]; then
      echo "Erro: use --cmd \"comando\"" >&2
      usage
      exit 1
    fi
    run_command_cluster "$2"
    ;;

  -h|--help)
    usage
    ;;

  *)
    echo "Erro: opção inválida: $1" >&2
    usage
    exit 1
    ;;
esac
