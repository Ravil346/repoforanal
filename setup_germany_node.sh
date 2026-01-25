#!/bin/bash

# ===========================================
# НАСТРОЙКА БЕЗОПАСНОСТИ НОДЫ ГЕРМАНИЯ v2.5+
# de.meerguard.net - порты 443 + 8443 (xhttp)
# Версия 2.0 - работает с docker-compose.yml
# ===========================================

set -e

# === КОНФИГУРАЦИЯ ===
PANEL_IP="91.208.184.247"  # IP панели panel.meerguard.net
NEW_SSH_PORT=41022
NEW_NODE_PORT=47891
VPN_PORTS="443 8443"  # Германия использует оба порта!

# === ЦВЕТА ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# === ПРОВЕРКИ ===
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Запусти скрипт от root: sudo bash $0"
        exit 1
    fi
}

find_compose_file() {
    log_info "Ищу docker-compose.yml ноды..."
    
    if [[ -f /opt/remnanode/docker-compose.yml ]]; then
        COMPOSE_FILE="/opt/remnanode/docker-compose.yml"
        COMPOSE_DIR="/opt/remnanode"
    elif [[ -f /root/remnanode/docker-compose.yml ]]; then
        COMPOSE_FILE="/root/remnanode/docker-compose.yml"
        COMPOSE_DIR="/root/remnanode"
    else
        log_error "Файл docker-compose.yml не найден в /opt/remnanode/ или /root/remnanode/"
        echo "Введи полный путь к docker-compose.yml:"
        read -r COMPOSE_FILE
        if [[ ! -f "$COMPOSE_FILE" ]]; then
            log_error "Файл не найден: $COMPOSE_FILE"
            exit 1
        fi
        COMPOSE_DIR="$(dirname "$COMPOSE_FILE")"
    fi
    
    log_ok "Найден: $COMPOSE_FILE"
    
    # Извлекаем NODE_PORT из docker-compose.yml
    CURRENT_NODE_PORT=$(grep -E "NODE_PORT" "$COMPOSE_FILE" | grep -oE '[0-9]+' | head -1)
    
    if [[ -z "$CURRENT_NODE_PORT" ]]; then
        log_error "Переменная NODE_PORT не найдена в $COMPOSE_FILE"
        exit 1
    fi
    
    log_ok "Текущий NODE_PORT: $CURRENT_NODE_PORT"
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
    echo "ПЛАН ДЕЙСТВИЙ (ГЕРМАНИЯ)"
    echo "=========================================="
    echo "1. SSH порт: $CURRENT_SSH_PORT → $NEW_SSH_PORT"
    echo "2. NODE_PORT: $CURRENT_NODE_PORT → $NEW_NODE_PORT (только для $PANEL_IP)"
    echo "3. VPN порты: $VPN_PORTS (открыты для всех)"
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

# === УСТАНОВКА UFW ===
install_ufw() {
    if ! command -v ufw &> /dev/null; then
        log_info "UFW не установлен. Устанавливаю..."
        apt-get update -qq
        apt-get install -y -qq ufw
        log_ok "UFW установлен"
    else
        log_ok "UFW уже установлен"
    fi
}

# === НАСТРОЙКА SSH ===
change_ssh() {
    log_info "Меняю SSH порт..."
    
    # Бэкап
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Меняем порт в основном конфиге
    if grep -q "^Port " /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    elif grep -q "^#Port " /etc/ssh/sshd_config; then
        sed -i "s/^#Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    else
        echo "Port $NEW_SSH_PORT" >> /etc/ssh/sshd_config
    fi
    
    # КРИТИЧНО: Сначала отключаем ssh.socket (Ubuntu 22.04+)
    if systemctl list-unit-files | grep -q "ssh.socket"; then
        log_info "Обнаружен ssh.socket, отключаю..."
        systemctl stop ssh.socket 2>/dev/null || true
        systemctl disable ssh.socket 2>/dev/null || true
        sleep 1
    fi
    
    # Определяем имя сервиса
    if systemctl list-unit-files | grep -q "^ssh.service"; then
        SSH_SERVICE="ssh"
    elif systemctl list-unit-files | grep -q "^sshd.service"; then
        SSH_SERVICE="sshd"
    else
        log_error "Не найден ssh/sshd service"
        exit 1
    fi
    
    # Останавливаем SSH полностью
    systemctl stop $SSH_SERVICE 2>/dev/null || true
    sleep 3
    
    # Включаем и запускаем SSH service
    systemctl enable $SSH_SERVICE 2>/dev/null || true
    systemctl start $SSH_SERVICE
    sleep 2
    
    # Проверяем что SSH слушает на IPv4
    if ss -tlnp | grep -q "0.0.0.0:$NEW_SSH_PORT"; then
        log_ok "SSH слушает на 0.0.0.0:$NEW_SSH_PORT (IPv4)"
    elif ss -tlnp | grep -q "\[::\]:$NEW_SSH_PORT"; then
        log_warn "SSH слушает только на IPv6, пробую перезапустить..."
        systemctl stop $SSH_SERVICE
        sleep 3
        systemctl start $SSH_SERVICE
        sleep 2
        
        if ss -tlnp | grep -q "0.0.0.0:$NEW_SSH_PORT"; then
            log_ok "SSH теперь слушает на IPv4"
        else
            log_error "SSH слушает только на IPv6!"
            log_error "Это опасно - UFW заблокирует соединение."
            echo ""
            echo "РУЧНОЕ ИСПРАВЛЕНИЕ:"
            echo "1. systemctl stop ssh.socket"
            echo "2. systemctl disable ssh.socket"
            echo "3. systemctl restart $SSH_SERVICE"
            echo "4. Запусти скрипт снова"
            exit 1
        fi
    else
        log_error "SSH не слушает на порту $NEW_SSH_PORT!"
        exit 1
    fi
    
    log_ok "SSH настроен на порту $NEW_SSH_PORT"
}

# === НАСТРОЙКА UFW ===
setup_ufw() {
    log_info "Настраиваю UFW..."
    
    # Сброс правил
    ufw --force reset
    
    # Политика по умолчанию
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH (для всех)
    ufw allow $NEW_SSH_PORT/tcp comment 'SSH'
    
    # NODE_PORT (только для панели!)
    ufw allow from $PANEL_IP to any port $NEW_NODE_PORT proto tcp comment 'RemnaWave Panel'
    
    # VPN порты (для всех) - 443 и 8443 для Германии!
    ufw allow 443/tcp comment 'VPN VLESS'
    ufw allow 8443/tcp comment 'VPN xHTTP'
    
    # Включаем
    ufw --force enable
    
    # Удаляем IPv6 правила
    log_info "Удаляю лишние IPv6 правила..."
    for i in $(ufw status numbered | grep "(v6)" | awk -F'[][]' '{print $2}' | sort -rn); do
        ufw --force delete $i
    done
    
    log_ok "UFW настроен (только IPv4)"
}

# === НАСТРОЙКА NODE_PORT ===
change_node_port() {
    log_info "Меняю NODE_PORT в docker-compose.yml..."
    
    # Бэкап
    cp "$COMPOSE_FILE" "${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Меняем NODE_PORT (формат: - NODE_PORT=XXXX)
    sed -i "s/NODE_PORT=$CURRENT_NODE_PORT/NODE_PORT=$NEW_NODE_PORT/" "$COMPOSE_FILE"
    
    # Проверяем изменение
    if grep -q "NODE_PORT=$NEW_NODE_PORT" "$COMPOSE_FILE"; then
        log_ok "NODE_PORT изменён на $NEW_NODE_PORT"
    else
        log_error "Не удалось изменить NODE_PORT!"
        exit 1
    fi
    
    # Перезапуск ноды
    log_info "Перезапускаю ноду..."
    cd "$COMPOSE_DIR"
    docker compose down && docker compose up -d
    
    log_ok "Нода перезапущена"
}

# === ФИНАЛЬНЫЙ ОТЧЁТ ===
final_report() {
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}     ФИНАЛЬНЫЙ ОТЧЁТ (ГЕРМАНИЯ)           ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    
    # SSH статус
    echo "=== SSH ==="
    echo -n "Сервис: "
    if systemctl is-active ssh &>/dev/null || systemctl is-active sshd &>/dev/null; then
        echo -e "${GREEN}активен${NC}"
    else
        echo -e "${RED}не активен!${NC}"
    fi
    echo -n "Порт $NEW_SSH_PORT (IPv4): "
    if ss -tlnp | grep -q "0.0.0.0:$NEW_SSH_PORT"; then
        echo -e "${GREEN}слушает ✓${NC}"
    else
        echo -e "${RED}не слушает!${NC}"
    fi
    echo ""
    
    # UFW статус
    echo "=== UFW ==="
    ufw status numbered
    echo ""
    
    # NODE_PORT
    echo "=== NODE_PORT ==="
    echo -n "В docker-compose.yml: "
    grep "NODE_PORT" "$COMPOSE_FILE" | head -1
    echo ""
    
    # Docker
    echo "=== DOCKER ==="
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "remna|NAME" || echo "Контейнеры не найдены"
    echo ""
    
    # Порты
    echo "=== СЛУШАЮЩИЕ ПОРТЫ ==="
    ss -tlnp | grep -E "($NEW_SSH_PORT|$NEW_NODE_PORT|:443|:8443)" | head -10
    echo ""
    
    # Итог
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}         СЛЕДУЮЩИЕ ШАГИ                   ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo "1. Открой НОВУЮ SSH сессию на порту $NEW_SSH_PORT:"
    echo "   ssh -p $NEW_SSH_PORT root@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "2. Если вход работает — старый порт уже закрыт"
    echo ""
    echo "3. В панели RemnaWave измени порт ноды на $NEW_NODE_PORT"
    echo ""
    echo -e "${YELLOW}Нода будет офлайн пока не изменишь порт в панели!${NC}"
    echo ""
}

# === MAIN ===
clear
echo "=== НАСТРОЙКА БЕЗОПАСНОСТИ ГЕРМАНИИ (v2.5+) ==="
echo ""

check_root
find_compose_file
get_current_ssh_port
show_plan
install_ufw
change_ssh
setup_ufw
change_node_port
final_report