#!/bin/bash
#===============================================================================
# VPN Node Optimization Script v3
# Оптимизация sysctl для VPN нод (BBR, буферы, лимиты)
# 
# Использование:
#   Интерактивно:  sudo bash vpn-node-optimize.sh
#   Через curl:    curl -sL URL | sudo bash -s -- --no-restart
#   Авто-рестарт:  curl -sL URL | sudo bash -s -- --restart
#
# Безопасно запускать повторно - скрипт проверяет существующие настройки
#===============================================================================

set -e

# Параметры
RESTART_DOCKER=false
NO_RESTART=false
AUTO_MODE=false

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --restart)
            RESTART_DOCKER=true
            AUTO_MODE=true
            shift
            ;;
        --no-restart)
            NO_RESTART=true
            AUTO_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}       VPN Node Optimization Script v3${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

#-------------------------------------------------------------------------------
# 1. Проверка root прав
#-------------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ОШИБКА] Этот скрипт должен запускаться с правами root${NC}"
   echo "Используйте: sudo bash $0"
   exit 1
fi

echo -e "${GREEN}[✓] Root права подтверждены${NC}"

#-------------------------------------------------------------------------------
# 2. Включение BBR
#-------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}>>> Настройка BBR...${NC}"

# Загрузить модуль BBR если не загружен
if lsmod | grep -q tcp_bbr; then
    echo -e "${GREEN}[✓] Модуль tcp_bbr уже загружен${NC}"
else
    echo "[*] Загружаю модуль tcp_bbr..."
    if modprobe tcp_bbr 2>/dev/null; then
        echo -e "${GREEN}[✓] Модуль tcp_bbr загружен${NC}"
    else
        echo -e "${YELLOW}[!] Не удалось загрузить tcp_bbr (может потребоваться перезагрузка)${NC}"
    fi
fi

# Добавить в автозагрузку (только если еще не добавлен)
if [ -f /etc/modules-load.d/bbr.conf ] && grep -q "tcp_bbr" /etc/modules-load.d/bbr.conf; then
    echo -e "${GREEN}[✓] BBR уже в автозагрузке${NC}"
else
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
    echo -e "${GREEN}[✓] BBR добавлен в автозагрузку${NC}"
fi

#-------------------------------------------------------------------------------
# 3. Настройки sysctl
#-------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}>>> Применение sysctl настроек...${NC}"

cat > /etc/sysctl.d/99-vpn-optimization.conf << 'EOF'
#===============================================================================
# VPN Node Optimization - sysctl settings
# Создано: vpn-node-optimize.sh
#===============================================================================

# BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Buffers (увеличены для высокой пропускной способности)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Connection Backlog (для большого количества соединений)
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.core.netdev_max_backlog = 16384

# TCP Fast Open (ускорение handshake)
net.ipv4.tcp_fastopen = 3

# Keepalive (обнаружение мертвых соединений)
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Timeouts (быстрое освобождение ресурсов)
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# IP Forwarding (для VPN)
net.ipv4.ip_forward = 1
EOF

# Применить настройки
if sysctl -p /etc/sysctl.d/99-vpn-optimization.conf > /dev/null 2>&1; then
    echo -e "${GREEN}[✓] Sysctl настройки применены${NC}"
else
    echo -e "${YELLOW}[!] Некоторые настройки могут требовать перезагрузку${NC}"
fi

#-------------------------------------------------------------------------------
# 4. Увеличение лимитов для Docker
#-------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}>>> Настройка лимитов Docker...${NC}"

mkdir -p /etc/systemd/system/docker.service.d

cat > /etc/systemd/system/docker.service.d/limits.conf << 'EOF'
[Service]
LimitNOFILE=65535
LimitNPROC=65535
EOF

echo -e "${GREEN}[✓] Лимиты Docker настроены${NC}"

# Перезагрузка systemd
systemctl daemon-reload
echo -e "${GREEN}[✓] Systemd перезагружен${NC}"

#-------------------------------------------------------------------------------
# 5. Перезапуск Docker (с учётом режима)
#-------------------------------------------------------------------------------
echo ""

if [ "$AUTO_MODE" = true ]; then
    # Автоматический режим (через curl)
    if [ "$RESTART_DOCKER" = true ]; then
        echo -e "${YELLOW}[*] Перезапуск Docker (--restart)...${NC}"
        systemctl restart docker
        echo -e "${GREEN}[✓] Docker перезапущен${NC}"
    else
        echo -e "${YELLOW}[!] Docker НЕ перезапущен (--no-restart)${NC}"
        echo -e "${YELLOW}    Выполните позже: systemctl restart docker${NC}"
    fi
else
    # Интерактивный режим
    echo -e "${YELLOW}=================================================================${NC}"
    echo -e "${YELLOW}  ВНИМАНИЕ: Для применения лимитов Docker требуется перезапуск${NC}"
    echo -e "${YELLOW}  Это перезапустит ВСЕ контейнеры!${NC}"
    echo -e "${YELLOW}=================================================================${NC}"
    echo ""
    read -p "Перезапустить Docker сейчас? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "[*] Перезапускаю Docker..."
        systemctl restart docker
        echo -e "${GREEN}[✓] Docker перезапущен${NC}"
        RESTART_DOCKER=true
    else
        echo -e "${YELLOW}[!] Docker НЕ перезапущен. Выполните позже: systemctl restart docker${NC}"
    fi
fi

#-------------------------------------------------------------------------------
# 6. Проверка и вывод результатов
#-------------------------------------------------------------------------------
echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}                  РЕЗУЛЬТАТЫ ОПТИМИЗАЦИИ${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

echo -e "${YELLOW}--- BBR ---${NC}"
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "не определено")
CURRENT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "не определено")
if [ "$CURRENT_CC" = "bbr" ]; then
    echo -e "tcp_congestion_control: ${GREEN}$CURRENT_CC ✓${NC}"
else
    echo -e "tcp_congestion_control: ${RED}$CURRENT_CC ✗ (требуется перезагрузка)${NC}"
fi
echo "default_qdisc: $CURRENT_QDISC"

echo ""
echo -e "${YELLOW}--- TCP Buffers ---${NC}"
RMEM=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "?")
WMEM=$(sysctl -n net.core.wmem_max 2>/dev/null || echo "?")
if [ "$RMEM" = "16777216" ]; then
    echo -e "rmem_max: ${GREEN}$RMEM ✓${NC}"
else
    echo -e "rmem_max: ${YELLOW}$RMEM${NC} (target: 16777216)"
fi
if [ "$WMEM" = "16777216" ]; then
    echo -e "wmem_max: ${GREEN}$WMEM ✓${NC}"
else
    echo -e "wmem_max: ${YELLOW}$WMEM${NC} (target: 16777216)"
fi
echo "tcp_rmem: $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
echo "tcp_wmem: $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"

echo ""
echo -e "${YELLOW}--- Connection Settings ---${NC}"
SOMAXCONN=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "?")
if [ "$SOMAXCONN" = "65535" ]; then
    echo -e "somaxconn: ${GREEN}$SOMAXCONN ✓${NC}"
else
    echo -e "somaxconn: ${YELLOW}$SOMAXCONN${NC} (target: 65535)"
fi
echo "tcp_max_syn_backlog: $(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null)"
echo "tcp_fastopen: $(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)"

echo ""
echo -e "${YELLOW}--- Timeouts ---${NC}"
echo "tcp_fin_timeout: $(sysctl -n net.ipv4.tcp_fin_timeout 2>/dev/null) (target: 15)"
echo "tcp_tw_reuse: $(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null) (target: 1)"
echo "tcp_keepalive_time: $(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null) (target: 600)"

echo ""
echo -e "${YELLOW}--- Docker Limits ---${NC}"
if [ -f /etc/systemd/system/docker.service.d/limits.conf ]; then
    echo -e "limits.conf: ${GREEN}создан ✓${NC}"
    grep -E "^Limit" /etc/systemd/system/docker.service.d/limits.conf
else
    echo -e "limits.conf: ${RED}не найден ✗${NC}"
fi

echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}                    ОПТИМИЗАЦИЯ ЗАВЕРШЕНА${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo ""

# Итоговые рекомендации
if [ "$RESTART_DOCKER" = false ]; then
    echo -e "${YELLOW}[!] Не забудьте перезапустить Docker: systemctl restart docker${NC}"
fi

if [ "$CURRENT_CC" != "bbr" ]; then
    echo -e "${YELLOW}[!] BBR может потребовать перезагрузку сервера для активации${NC}"
fi

echo -e "${GREEN}[✓] Настройки сохранены и будут работать после перезагрузки${NC}"
echo ""
