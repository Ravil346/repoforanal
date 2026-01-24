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
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

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
    # Это нужно сделать ДО перезапуска SSH, иначе будет только IPv6
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
    
    # Ждём освобождения порта
    sleep 3
    
    # Включаем и запускаем SSH service
    systemctl enable $SSH_SERVICE 2>/dev/null || true
    systemctl start $SSH_SERVICE
    
    # Ждём запуска
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
            # Критическая проверка - не продолжаем если только IPv6
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
    
    # VPN порты (для всех)
    ufw allow 443/tcp comment 'VPN VLESS'
    
    # Включаем
    ufw --force enable
    
    # Удаляем IPv6 правила (не нужны, серверы без глобального IPv6)
    log_info "Удаляю лишние IPv6 правила..."
    
    # Получаем номера IPv6 правил и удаляем с конца
    for i in $(ufw status numbered | grep "(v6)" | awk -F'[][]' '{print $2}' | sort -rn); do
        ufw --force delete $i
    done
    
    log_ok "UFW настроен (только IPv4)"
}

# === НАСТРОЙКА NODE_PORT ===
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

# === ФИНАЛЬНЫЙ ОТЧЁТ ===
final_report() {
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}         ФИНАЛЬНЫЙ ОТЧЁТ                  ${NC}"
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
    echo -n "Порт $NEW_SSH_PORT (IPv6): "
    if ss -tlnp | grep -q "\[::\]:$NEW_SSH_PORT"; then
        echo -e "${GREEN}слушает ✓${NC}"
    else
        echo -e "${YELLOW}не слушает${NC}"
    fi
    echo ""
    
    # UFW статус
    echo "=== UFW ==="
    ufw status numbered
    echo ""
    
    # APP_PORT
    echo "=== APP_PORT ==="
    echo -n "В .env: "
    grep "^APP_PORT=" "$ENV_FILE"
    echo ""
    
    # Docker
    echo "=== DOCKER ==="
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "remna|NAME" || echo "Контейнеры не найдены"
    echo ""
    
    # Порты
    echo "=== СЛУШАЮЩИЕ ПОРТЫ ==="
    ss -tlnp | grep -E "($NEW_SSH_PORT|$NEW_NODE_PORT|:443)" | head -10
    echo ""
    
    # Итог
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}         СЛЕДУЮЩИЕ ШАГИ                   ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo ""
    echo "1. Открой НОВУЮ SSH сессию на порту $NEW_SSH_PORT:"
    echo "   ssh -p $NEW_SSH_PORT root@$(hostname -I | awk '{print $1}')"
    echo ""
    echo "2. Если вход работает — удали старый порт:"
    echo "   ufw delete allow 22/tcp"
    echo ""
    echo "3. В панели RemnaWave измени порт ноды на $NEW_NODE_PORT"
    echo ""
    echo -e "${YELLOW}Нода будет офлайн пока не изменишь порт в панели!${NC}"
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
install_ufw
change_ssh
setup_ufw
change_node_port
final_report