#!/bin/bash

#===============================================================================
# СКРИПТ НАСТРОЙКИ БЕЗОПАСНОСТИ НОД REMNAWAVE
# Версия: 1.0
# 
# Что делает:
# 1. Настраивает UFW файрволл
# 2. Меняет SSH порт на нестандартный
# 3. Меняет NODE_PORT в .env
# 4. Открывает только нужные порты
#
# ВАЖНО: Запускать от root!
#===============================================================================

set -e

# ====== КОНФИГУРАЦИЯ (ИЗМЕНИ ПОД СЕБЯ) ======
NEW_SSH_PORT=41022
NEW_NODE_PORT=47891
PANEL_IP="91.208.184.247"  # IP панели panel.meerguard.net

# Порты VPN (443 для всех, 8443 только для Германии с xhttp)
VPN_PORTS="443"
# Раскомментируй для Германии (de.meerguard.net):
# VPN_PORTS="443 8443"

# ====== ЦВЕТА ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ====== ФУНКЦИИ ======
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт нужно запускать от root!"
        exit 1
    fi
}

check_panel_ip() {
    if [[ -z "$PANEL_IP" ]]; then
        log_error "PANEL_IP не задан!"
        echo ""
        echo "Узнай IP панели командой:"
        echo "  dig +short panel.meerguard.net"
        echo "  или: host panel.meerguard.net"
        echo ""
        echo "Затем отредактируй скрипт и впиши IP в переменную PANEL_IP"
        exit 1
    fi
    log_ok "IP панели: $PANEL_IP"
}

show_current_state() {
    echo ""
    echo "=========================================="
    echo "ТЕКУЩЕЕ СОСТОЯНИЕ"
    echo "=========================================="
    
    # SSH порт
    CURRENT_SSH_PORT=$(grep -E "^#?Port " /etc/ssh/sshd_config | tail -1 | awk '{print $2}')
    if [[ -z "$CURRENT_SSH_PORT" ]]; then
        CURRENT_SSH_PORT=22
    fi
    log_info "Текущий SSH порт: $CURRENT_SSH_PORT"
    
    # NODE_PORT
    if [[ -f /opt/remnanode/.env ]]; then
        CURRENT_NODE_PORT=$(grep -E "^(APP_PORT|NODE_PORT)=" /opt/remnanode/.env | head -1 | cut -d'=' -f2)
        log_info "Текущий NODE_PORT: $CURRENT_NODE_PORT"
        ENV_FILE="/opt/remnanode/.env"
    elif [[ -f /root/remnanode/.env ]]; then
        CURRENT_NODE_PORT=$(grep -E "^(APP_PORT|NODE_PORT)=" /root/remnanode/.env | head -1 | cut -d'=' -f2)
        log_info "Текущий NODE_PORT: $CURRENT_NODE_PORT"
        ENV_FILE="/root/remnanode/.env"
    else
        log_warn "Файл .env не найден в /opt/remnanode/ или /root/remnanode/"
        log_info "Введи путь к .env файлу ноды:"
        read -r ENV_FILE
        if [[ -f "$ENV_FILE" ]]; then
            CURRENT_NODE_PORT=$(grep -E "^(APP_PORT|NODE_PORT)=" "$ENV_FILE" | head -1 | cut -d'=' -f2)
            log_info "Текущий NODE_PORT: $CURRENT_NODE_PORT"
        else
            log_error "Файл не найден: $ENV_FILE"
            exit 1
        fi
    fi
    
    # UFW статус
    if command -v ufw &> /dev/null; then
        UFW_STATUS=$(ufw status | head -1)
        log_info "UFW: $UFW_STATUS"
    else
        log_warn "UFW не установлен"
    fi
    
    # Слушающие порты
    echo ""
    log_info "Порты в LISTEN:"
    ss -tlnp | grep -E "LISTEN" | head -15
    echo ""
}

confirm_action() {
    echo ""
    echo "=========================================="
    echo "ПЛАН ДЕЙСТВИЙ"
    echo "=========================================="
    echo "1. Установить UFW (если не установлен)"
    echo "2. Изменить SSH порт: $CURRENT_SSH_PORT -> $NEW_SSH_PORT"
    echo "3. Изменить NODE_PORT: $CURRENT_NODE_PORT -> $NEW_NODE_PORT"
    echo "4. Настроить файрволл:"
    echo "   - SSH ($NEW_SSH_PORT): открыт для всех"
    echo "   - NODE_PORT ($NEW_NODE_PORT): открыт ТОЛЬКО для $PANEL_IP"
    echo "   - VPN порты ($VPN_PORTS): открыты для всех"
    echo "   - Всё остальное: закрыто"
    echo ""
    echo -e "${YELLOW}ВНИМАНИЕ: Убедись что у тебя открыта вторая SSH сессия на случай проблем!${NC}"
    echo ""
    read -p "Продолжить? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        log_warn "Отменено пользователем"
        exit 0
    fi
}

install_ufw() {
    log_info "Проверяю UFW..."
    if ! command -v ufw &> /dev/null; then
        log_info "Устанавливаю UFW..."
        apt-get update -qq
        apt-get install -y ufw
        log_ok "UFW установлен"
    else
        log_ok "UFW уже установлен"
    fi
}

configure_ufw() {
    log_info "Настраиваю UFW..."
    
    # Сначала отключаем чтобы не заблокировать себя
    ufw --force disable
    
    # Сбрасываем все правила
    ufw --force reset
    
    # Политика по умолчанию
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH (новый порт) - для всех
    ufw allow $NEW_SSH_PORT/tcp comment 'SSH'
    log_ok "Разрешён SSH на порту $NEW_SSH_PORT"
    
    # SSH (старый порт) - временно оставляем до проверки
    ufw allow $CURRENT_SSH_PORT/tcp comment 'SSH-old-temp'
    log_ok "Временно оставлен старый SSH порт $CURRENT_SSH_PORT"
    
    # NODE_PORT - только для панели
    ufw allow from $PANEL_IP to any port $NEW_NODE_PORT proto tcp comment 'RemnaWave-Panel'
    log_ok "Разрешён NODE_PORT $NEW_NODE_PORT только для $PANEL_IP"
    
    # VPN порты - для всех
    for port in $VPN_PORTS; do
        ufw allow $port/tcp comment 'VPN'
        ufw allow $port/udp comment 'VPN-UDP'
        log_ok "Разрешён VPN порт $port"
    done
    
    # Включаем UFW
    ufw --force enable
    log_ok "UFW включён"
    
    # Показываем правила
    echo ""
    log_info "Текущие правила UFW:"
    ufw status numbered
}

change_ssh_port() {
    log_info "Изменяю SSH порт..."
    
    # Бэкап конфига
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    
    # Меняем порт
    if grep -q "^Port " /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    elif grep -q "^#Port " /etc/ssh/sshd_config; then
        sed -i "s/^#Port .*/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
    else
        echo "Port $NEW_SSH_PORT" >> /etc/ssh/sshd_config
    fi
    
    log_ok "SSH порт изменён на $NEW_SSH_PORT в конфиге"
    
    # Перезапускаем SSH
    systemctl restart sshd
    log_ok "SSH перезапущен"
}

change_node_port() {
    log_info "Изменяю NODE_PORT в $ENV_FILE..."
    
    # Бэкап
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Проверяем какая переменная используется (APP_PORT или NODE_PORT)
    if grep -q "^APP_PORT=" "$ENV_FILE"; then
        sed -i "s/^APP_PORT=.*/APP_PORT=$NEW_NODE_PORT/" "$ENV_FILE"
        log_ok "APP_PORT изменён на $NEW_NODE_PORT"
    elif grep -q "^NODE_PORT=" "$ENV_FILE"; then
        sed -i "s/^NODE_PORT=.*/NODE_PORT=$NEW_NODE_PORT/" "$ENV_FILE"
        log_ok "NODE_PORT изменён на $NEW_NODE_PORT"
    else
        echo "NODE_PORT=$NEW_NODE_PORT" >> "$ENV_FILE"
        log_ok "NODE_PORT добавлен: $NEW_NODE_PORT"
    fi
    
    # Перезапускаем контейнер
    log_info "Перезапускаю контейнер remnanode..."
    cd "$(dirname "$ENV_FILE")"
    docker compose down
    docker compose up -d
    log_ok "Контейнер перезапущен"
}

verify_changes() {
    echo ""
    echo "=========================================="
    echo "ПРОВЕРКА"
    echo "=========================================="
    
    # Проверяем SSH
    NEW_SSH_LISTENING=$(ss -tlnp | grep ":$NEW_SSH_PORT " | wc -l)
    if [[ $NEW_SSH_LISTENING -gt 0 ]]; then
        log_ok "SSH слушает на порту $NEW_SSH_PORT"
    else
        log_error "SSH НЕ слушает на порту $NEW_SSH_PORT!"
    fi
    
    # Проверяем NODE_PORT
    sleep 5  # Ждём запуска контейнера
    NEW_NODE_LISTENING=$(ss -tlnp | grep ":$NEW_NODE_PORT " | wc -l)
    if [[ $NEW_NODE_LISTENING -gt 0 ]]; then
        log_ok "Нода слушает на порту $NEW_NODE_PORT"
    else
        log_warn "Нода пока не слушает на порту $NEW_NODE_PORT (может ещё запускается)"
    fi
    
    # Показываем итоговые порты
    echo ""
    log_info "Итоговые порты в LISTEN:"
    ss -tlnp | grep -E "LISTEN"
}

final_instructions() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}ГОТОВО!${NC}"
    echo "=========================================="
    echo ""
    echo "СЛЕДУЮЩИЕ ШАГИ:"
    echo ""
    echo "1. ОТКРОЙ НОВУЮ SSH СЕССИЮ на порту $NEW_SSH_PORT"
    echo "   ssh -p $NEW_SSH_PORT root@<IP-сервера>"
    echo ""
    echo "2. Если вход работает — удали временное правило старого SSH порта:"
    echo "   ufw delete allow $CURRENT_SSH_PORT/tcp"
    echo ""
    echo "3. В ПАНЕЛИ REMNAWAVE измени порт ноды на $NEW_NODE_PORT"
    echo "   (Настройки ноды -> Port -> $NEW_NODE_PORT)"
    echo ""
    echo "4. Проверь что нода подключилась к панели"
    echo ""
    echo "=========================================="
    echo "ОТКАТ (если что-то пошло не так):"
    echo "=========================================="
    echo "# Восстановить SSH конфиг:"
    echo "cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config"
    echo "systemctl restart sshd"
    echo ""
    echo "# Отключить файрволл:"
    echo "ufw disable"
    echo ""
    echo "# Восстановить .env:"
    echo "cp ${ENV_FILE}.backup.* $ENV_FILE"
    echo "cd $(dirname "$ENV_FILE") && docker compose down && docker compose up -d"
    echo ""
}

# ====== MAIN ======
clear
echo "=========================================="
echo "НАСТРОЙКА БЕЗОПАСНОСТИ НОДЫ REMNAWAVE"
echo "=========================================="

check_root
check_panel_ip
show_current_state
confirm_action
install_ufw
change_ssh_port
configure_ufw
change_node_port
verify_changes
final_instructions
