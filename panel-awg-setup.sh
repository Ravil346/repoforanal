#!/bin/bash
#
# AmneziaWG Server Setup for RemnaWave Panel
# Версия 2.0 - исправлена установка PPA
#

set -e

# ===== НАСТРОЙКИ =====
AWG_PORT=51820
AWG_INTERFACE="awg0"
AWG_ADDRESS="10.10.0.1/24"
AWG_CONFIG_DIR="/etc/amnezia/amneziawg"

# Обфускация (должны совпадать на всех пирах!)
JC=4
JMIN=40
JMAX=70
S1=0
S2=0
H1=1
H2=2
H3=3
H4=4

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  AmneziaWG Server Setup for Panel${NC}"
echo -e "${GREEN}  Версия 2.0${NC}"
echo -e "${GREEN}========================================${NC}"

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Запустите скрипт от root!${NC}"
   exit 1
fi

# 1. Установка AmneziaWG
echo -e "\n${YELLOW}[1/6] Установка AmneziaWG...${NC}"

if ! command -v awg &> /dev/null; then
    echo -e "${YELLOW}Добавляем репозиторий Amnezia (прямой метод)...${NC}"
    
    # Добавляем ключ напрямую (обход проблемы с launchpadlib)
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x57290828" | gpg --dearmor -o /usr/share/keyrings/amnezia.gpg
    
    # Добавляем репозиторий (focal работает для Ubuntu 24.04)
    echo "deb [signed-by=/usr/share/keyrings/amnezia.gpg] https://ppa.launchpadcontent.net/amnezia/ppa/ubuntu focal main" | tee /etc/apt/sources.list.d/amnezia.list
    
    # Устанавливаем зависимости и AWG
    apt-get update
    apt-get install -y linux-headers-$(uname -r)
    apt-get install -y amneziawg amneziawg-tools
    
    # Загружаем модуль
    modprobe amneziawg
    
    echo -e "${GREEN}AmneziaWG установлен${NC}"
else
    echo -e "${GREEN}AmneziaWG уже установлен${NC}"
    modprobe amneziawg 2>/dev/null || true
fi

# Проверка модуля
if ! lsmod | grep -q amneziawg; then
    echo -e "${RED}Модуль amneziawg не загружен!${NC}"
    exit 1
fi

# 2. Генерация ключей
echo -e "\n${YELLOW}[2/6] Генерация ключей...${NC}"

mkdir -p "$AWG_CONFIG_DIR"
cd "$AWG_CONFIG_DIR"

if [[ ! -f privatekey ]]; then
    awg genkey | tee privatekey | awg pubkey > publickey
    chmod 600 privatekey
    echo -e "${GREEN}Ключи сгенерированы${NC}"
else
    echo -e "${GREEN}Ключи уже существуют${NC}"
fi

PRIVATE_KEY=$(cat privatekey)
PUBLIC_KEY=$(cat publickey)

# 3. Создание конфига сервера
echo -e "\n${YELLOW}[3/6] Создание конфигурации...${NC}"

cat > "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf" << EOF
[Interface]
Address = $AWG_ADDRESS
ListenPort = $AWG_PORT
PrivateKey = $PRIVATE_KEY

# Обфускация (эти значения должны совпадать на всех пирах!)
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

# Пиры добавляются через add-peer.sh

EOF

chmod 600 "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf"

# 4. Настройка файрвола
echo -e "\n${YELLOW}[4/6] Настройка файрвола...${NC}"

if command -v ufw &> /dev/null; then
    ufw allow ${AWG_PORT}/udp comment "AmneziaWG" 2>/dev/null || true
    echo -e "${GREEN}Порт $AWG_PORT/udp открыт${NC}"
else
    echo -e "${YELLOW}UFW не установлен, открой порт $AWG_PORT/udp вручную${NC}"
fi

# 5. Создание systemd сервиса
echo -e "\n${YELLOW}[5/6] Настройка автозапуска...${NC}"

cat > /etc/systemd/system/awg-quick@.service << 'EOF'
[Unit]
Description=AmneziaWG via awg-quick(8) for %I
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/awg-quick up %i
ExecStop=/usr/bin/awg-quick down %i

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable awg-quick@$AWG_INTERFACE

# 6. Запуск
echo -e "\n${YELLOW}[6/6] Запуск AmneziaWG...${NC}"

# Останавливаем если уже запущен
awg-quick down $AWG_INTERFACE 2>/dev/null || true

# Запускаем
awg-quick up $AWG_INTERFACE

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Публичный ключ сервера (сохрани!):"
echo -e "${YELLOW}$PUBLIC_KEY${NC}"
echo ""
echo -e "Этот ключ нужен для настройки нод и админа."
echo ""
echo -e "IP панели в AWG сети: ${YELLOW}10.10.0.1${NC}"
echo -e "Порт AWG: ${YELLOW}$AWG_PORT/udp${NC}"
echo ""
echo -e "Для добавления ноды используй:"
echo -e "${YELLOW}./add-peer.sh <имя> <публичный_ключ_ноды> <awg_ip>${NC}"
echo ""
echo -e "Проверка статуса: ${YELLOW}awg show${NC}"
echo ""

# Показываем статус
awg show