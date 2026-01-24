#!/bin/bash

#===============================================================================
# СКРИПТ ДЛЯ ГЕРМАНИИ (de.meerguard.net) С ПОРТОМ 8443
# 
# Отличие от стандартного: открыт порт 8443 для xhttp
#===============================================================================

set -e

# ====== КОНФИГУРАЦИЯ ======
NEW_SSH_PORT=41022
NEW_NODE_PORT=47891
PANEL_IP="91.208.184.247"  # IP панели panel.meerguard.net

# Для Германии: 443 + 8443
VPN_PORTS="443 8443"

# ====== ЦВЕТА ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Запусти от root!"
        exit 1
    fi
}

check_panel_ip() {
    if [[ -z "$PANEL_IP" ]]; then
        log_error "PANEL_IP не задан!"
        echo "Узнай: dig +short panel.meerguard.net"
        exit 1
    fi
    log_ok "IP панели: $PANEL_IP"
}

find_env_file() {
    if [[ -f /opt/remnanode/.env ]]; then
        ENV_FILE="/opt/remnanode/.env"
    elif [[ -f /root/remnanode/.env ]]; then
        ENV_FILE="/root/remnanode/.env"
    else
        log_warn "Файл .env не найден"
        read -p "Введи путь к .env: " ENV_FILE
    fi
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Файл не найден: $ENV_FILE"
        exit 1
    fi
    
    CURRENT_NODE_PORT=$(grep -E "^(APP_PORT|NODE_PORT)=" "$ENV_FILE" | head -1 | cut -d'=' -f2)
    log_info "ENV файл: $ENV_FILE"
    log_info "Текущий NODE_PORT: $CURRENT_NODE_PORT"
}

get_current_ssh_port() {
    CURRENT_SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [[ -z "$CURRENT_SSH_PORT" ]]; then
        CURRENT_SSH_PORT=22
    fi
    log_info "Текущий SSH порт: $CURRENT_SSH_PORT"
}

show_plan() {
    echo ""
    echo "=========================================="
    echo "ПЛАН ДЕЙСТВИЙ (ГЕРМАНИЯ + 8443)"
    echo "=========================================="
    echo "SSH: $CURRENT_SSH_PORT -> $NEW_SSH_PORT"
    echo "NODE_PORT: $CURRENT_NODE_PORT -> $NEW_NODE_PORT"
    echo "VPN порты: $VPN_PORTS (включая 8443 для xhttp)"
    echo "NODE_PORT открыт только для: $PANEL_IP"
    echo ""
    echo -e "${YELLOW}Держи открытой вторую SSH сессию!${NC}"
    read -p "Продолжить? (yes/no): " CONFIRM
    [[ "$CONFIRM" != "yes" ]] && exit 0
}

setup_ufw() {
    log_info "Настраиваю UFW..."
    
    apt-get update -qq && apt-get install -y ufw 2>/dev/null || true
    
    ufw --force disable
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH
    ufw allow $NEW_SSH_PORT/tcp comment 'SSH'
    ufw allow $CURRENT_SSH_PORT/tcp comment 'SSH-old-temp'
    
    # NODE_PORT только для панели
    ufw allow from $PANEL_IP to any port $NEW_NODE_PORT proto tcp comment 'Panel'
    
    # VPN порты
    for port in $VPN_PORTS; do
        ufw allow $port/tcp comment 'VPN'
        ufw allow $port/udp comment 'VPN-UDP'
    done
    
    ufw --force enable
    log_ok "UFW настроен"
    ufw status numbered
}

change_ssh() {
    log_info "Меняю SSH порт..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    if grep -q "^Port " /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    else
        sed -i "s/^#Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    fi
    
    systemctl restart sshd
    log_ok "SSH перезапущен на порту $NEW_SSH_PORT"
}

change_node_port() {
    log_info "Меняю NODE_PORT..."
    cp "$ENV_FILE" "${ENV_FILE}.bak"
    
    if grep -q "^APP_PORT=" "$ENV_FILE"; then
        sed -i "s/^APP_PORT=.*/APP_PORT=$NEW_NODE_PORT/" "$ENV_FILE"
    elif grep -q "^NODE_PORT=" "$ENV_FILE"; then
        sed -i "s/^NODE_PORT=.*/NODE_PORT=$NEW_NODE_PORT/" "$ENV_FILE"
    fi
    
    cd "$(dirname "$ENV_FILE")"
    docker compose down && docker compose up -d
    log_ok "Нода перезапущена"
}

verify() {
    echo ""
    sleep 3
    log_info "Проверка портов:"
    ss -tlnp | grep -E "($NEW_SSH_PORT|$NEW_NODE_PORT|443|8443)"
}

final_msg() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "ГОТОВО!"
    echo "==========================================${NC}"
    echo ""
    echo "1. Подключись по SSH на порту $NEW_SSH_PORT"
    echo "2. Если работает — удали старый порт:"
    echo "   ufw delete allow $CURRENT_SSH_PORT/tcp"
    echo "3. В панели измени порт ноды на $NEW_NODE_PORT"
    echo ""
}

# === MAIN ===
clear
echo "=== НАСТРОЙКА ГЕРМАНИИ (de.meerguard.net) ==="
check_root
check_panel_ip
find_env_file
get_current_ssh_port
show_plan
change_ssh
setup_ufw
change_node_port
verify
final_msg
