#!/usr/bin/env bash
set -euo pipefail
# =========================
# Exigir root
# =========================
if [[ "$EUID" -ne 0 ]]; then
  echo "Erro: este script precisa ser executado como root."
  echo "Use:"
  echo "  sudo $0 $*"
  exit 1
fi
# =========================
# Configuração do cluster
# =========================

TARGET_IP="11.0.0.1"

# Hostnames
HOSTS=(
  "stereo2"
  "mauro"
  "s5"
)

# MACs correspondentes
MACS=(
  "e0:d5:5e:f3:a3:90"  # stereo2
  "04:42:1a:93:e6:79"  # mauro
  "a4:bf:01:37:22:ba"  # s5
)

# =========================
# Funções
# =========================

usage() {
  cat <<EOF
Uso:
  $0 --on
  $0 --off
  $0 --help

Opções:
  --on    Liga todas as máquinas do cluster via Wake-on-LAN
  --off   Desliga todas as máquinas do cluster via SSH + poweroff
  -h, --help  Mostra esta ajuda
EOF
}

get_wol_interface() {
  local iface=""

  iface=$(ifconfig | awk -v ip="$TARGET_IP" '
    /^[a-zA-Z0-9]/ {gsub(":", "", $1); current_if=$1}
    $0 ~ ip {print current_if; exit}
  ')

  if [[ -z "$iface" ]]; then
    echo "Erro: não encontrei nenhuma interface com o IP $TARGET_IP." >&2
    echo "Verifique a saída do ifconfig e confirme se esse IP está atribuído a uma interface." >&2
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
    echo "-> Ligando ${host} (${mac})"
    sudo etherwake -D -b -i "$iface" "$mac"
    sleep 1
  done

  echo "Cluster ligado."
}

shutdown_cluster() {
  echo "Desligando cluster via SSH..."

  for host in "${HOSTS[@]}"; do
    echo "-> Desligando ${host}"
    if ssh "$host" "sudo poweroff"; then
      echo "   OK: ${host}"
    else
      echo "   Falha ao desligar ${host}"
    fi
  done

  echo "Comando de desligamento enviado para o cluster."
}

# =========================
# Execução principal
# =========================

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

case "$1" in
  --on)
    wake_cluster
    ;;
  --off)
    shutdown_cluster
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
