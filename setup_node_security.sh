#!/bin/bash

# ===========================================
# НАСТРОЙКА БЕЗОПАСНОСТИ НОДЫ RemnaWave
# Для всех нод с портом 443
# ===========================================

set -e

# === КОНФИГУРАЦИЯ ===
PANEL_IP="91.208.184.247"  # IP панели panel.meerguard.net
NEW_SSH_PORT=41022
NEW_NODE_PORT=47891
VPN_PORTS="443"

# === ЦВЕТА ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# === ПРОВЕРКИ ===
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Запусти скрипт от root: sudo bash $0"
        exit 1
    fi
}

find_env_file() {
    log_info "Ищу .env файл ноды..."
    
    if [[ -f /opt/remnanode/.env ]]; then
        ENV_FILE="/opt/remnanode/.env"
    elif [[ -f /root/remnanode/.env ]]; then
        ENV_FILE="/root/remnanode/.env"
    else
        log_error "Файл .env не найден в /opt/remnanode/ или /root/remnanode/"
        echo "Введи полный путь к .env файлу:"
        read -r ENV_FILE
        if [[ ! -f "$ENV_FILE" ]]; then
            log_error "Файл не найден: $ENV_FILE"
            exit 1
        fi
    fi
    
    log_ok "Найден: $ENV_FILE"
    
    # Проверяем что там APP_PORT
    if grep -q "^APP_PORT=" "$ENV_FILE"; then
        CURRENT_NODE_PORT=$(grep "^APP_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        log_ok "Текущий APP_PORT: $CURRENT_NODE_PORT"
    else
        log_error "Переменная APP_PORT не найдена в $ENV_FILE"
        exit 1
    fi
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
    echo "ПЛАН ДЕЙСТВИЙ"
    echo "=========================================="
    echo "1. SSH порт: $CURRENT_SSH_PORT → $NEW_SSH_PORT"
    echo "2. APP_PORT: $CURRENT_NODE_PORT → $NEW_NODE_PORT (только для $PANEL_IP)"
    echo "3. VPN порт: $VPN_PORTS (открыт для всех)"
    echo "4. Всё остальное: закрыто (UFW)"
    echo ""
    echo -e "${YELLOW}ВАЖНО: Держи вторую SSH сессию открытой!${NC}"
    echo ""
    read -p "Продолжить? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Отменено."
        exit 0
    fi
}

# === НАСТРОЙКА ===
setup_ufw() {
    log_info "Настраиваю UFW..."
    
    # Установка если нет
    if ! command -v ufw &> /dev/null; then
        apt-get update && apt-get install -y ufw
    fi
    
    # Сброс правил
    ufw --force reset
    
    # Политика по умолчанию
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH (для всех)
    ufw allow $NEW_SSH_PORT/tcp comment 'SSH'
    
    # NODE_PORT (только для панели!)
    ufw allow from $PANEL_IP to any port $NEW_NODE_PORT proto tcp comment 'RemnaWave Panel'
    
    # VPN порты (для всех)
    ufw allow $VPN_PORTS/tcp comment 'VPN'
    
    # Включаем
    ufw --force enable
    
    log_ok "UFW настроен"
    ufw status numbered
}

change_ssh() {
    log_info "Меняю SSH порт..."
    
    # Бэкап
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Меняем порт
    if grep -q "^Port " /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    elif grep -q "^#Port " /etc/ssh/sshd_config; then
        sed -i "s/^#Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    else
        echo "Port $NEW_SSH_PORT" >> /etc/ssh/sshd_config
    fi
    
    systemctl restart sshd
    log_ok "SSH перезапущен на порту $NEW_SSH_PORT"
}

change_node_port() {
    log_info "Меняю APP_PORT в .env..."
    
    # Бэкап
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Меняем ТОЛЬКО APP_PORT
    sed -i "s/^APP_PORT=.*/APP_PORT=$NEW_NODE_PORT/" "$ENV_FILE"
    
    log_ok "APP_PORT изменён на $NEW_NODE_PORT"
    
    # Перезапуск ноды
    log_info "Перезапускаю ноду..."
    cd "$(dirname "$ENV_FILE")"
    docker compose down && docker compose up -d
    
    log_ok "Нода перезапущена"
}

verify() {
    echo ""
    log_info "Проверка..."
    sleep 3
    
    echo ""
    echo "=== Слушающие порты ==="
    ss -tlnp | grep -E "($NEW_SSH_PORT|$NEW_NODE_PORT|443)" || true
    
    echo ""
    echo "=== UFW статус ==="
    ufw status
    
    echo ""
    echo "=== APP_PORT в .env ==="
    grep "^APP_PORT=" "$ENV_FILE"
}

final_message() {
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}ГОТОВО!${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo "СЛЕДУЮЩИЕ ШАГИ:"
    echo ""
    echo "1. Открой НОВУЮ сессию SSH на порту $NEW_SSH_PORT:"
    echo "   ssh -p $NEW_SSH_PORT root@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "2. Если вход работает — удали старый порт:"
    echo "   ufw delete allow $CURRENT_SSH_PORT/tcp"
    echo ""
    echo "3. В панели RemnaWave измени порт ноды на $NEW_NODE_PORT"
    echo ""
}

# === MAIN ===
clear
echo "=== НАСТРОЙКА БЕЗОПАСНОСТИ НОДЫ ==="
echo ""

check_root
find_env_file
get_current_ssh_port
show_plan
change_ssh
setup_ufw
change_node_port
verify
final_message