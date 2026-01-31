#!/bin/bash
#
# AmneziaWG Server Setup for RemnaWave Panel
# Запускать на сервере панели
#

set -e

# ===== НАСТРОЙКИ =====
AWG_PORT=51820
AWG_INTERFACE="awg0"
AWG_ADDRESS="10.10.0.1/24"
AWG_CONFIG_DIR="/etc/amnezia/amneziawg"

# Обфускация параметры (должны совпадать на всех пирах!)
JC=4        # Junk packet count
JMIN=40     # Junk packet minimum size
JMAX=70     # Junk packet maximum size
S1=0        # Init packet junk size
S2=0        # Response packet junk size
H1=1        # Init packet magic header
H2=2        # Response packet magic header
H3=3        # Under load packet magic header
H4=4        # Transport packet magic header

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  AmneziaWG Server Setup for Panel${NC}"
echo -e "${GREEN}========================================${NC}"

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Запустите скрипт от root!${NC}"
   exit 1
fi

# 1. Установка AmneziaWG
echo -e "\n${YELLOW}[1/5] Установка AmneziaWG...${NC}"

if ! command -v awg &> /dev/null; then
    # Добавляем репозиторий Amnezia
    apt-get update
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:amnezia/ppa
    apt-get update
    apt-get install -y amneziawg amneziawg-tools
    
    # Загружаем модуль
    modprobe amneziawg || {
        echo -e "${RED}Не удалось загрузить модуль amneziawg${NC}"
        echo -e "${YELLOW}Попробуем DKMS установку...${NC}"
        apt-get install -y amneziawg-dkms
        modprobe amneziawg
    }
else
    echo -e "${GREEN}AmneziaWG уже установлен${NC}"
fi

# 2. Генерация ключей
echo -e "\n${YELLOW}[2/5] Генерация ключей...${NC}"

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
echo -e "\n${YELLOW}[3/5] Создание конфигурации...${NC}"

cat > "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf" << EOF
[Interface]
Address = $AWG_ADDRESS
ListenPort = $AWG_PORT
PrivateKey = $PRIVATE_KEY

# AmneziaWG обфускация
Jc = $JC
Jmin = $JMIN
Jmax = $JMAX
S1 = $S1
S2 = $S2
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

# Пиры будут добавляться ниже
# Используй add-peer.sh для добавления нод

EOF

chmod 600 "$AWG_CONFIG_DIR/$AWG_INTERFACE.conf"

# 4. Настройка файрвола
echo -e "\n${YELLOW}[4/5] Настройка файрвола...${NC}"

ufw allow ${AWG_PORT}/udp comment "AmneziaWG"
echo -e "${GREEN}Порт $AWG_PORT/udp открыт${NC}"

# 5. Запуск сервиса
echo -e "\n${YELLOW}[5/5] Запуск AmneziaWG...${NC}"

# Создаём systemd сервис
cat > /etc/systemd/system/awg-quick@.service << 'EOF'
[Unit]
Description=AmneziaWG via awg-quick(8) for %I
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target
Documentation=man:awg-quick(8)
Documentation=man:awg(8)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/awg-quick up %i
ExecStop=/usr/bin/awg-quick down %i
Environment=WG_ENDPOINT_RESOLUTION_RETRIES=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable awg-quick@$AWG_INTERFACE
systemctl start awg-quick@$AWG_INTERFACE || awg-quick up $AWG_INTERFACE

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  Установка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Публичный ключ сервера:"
echo -e "${YELLOW}$PUBLIC_KEY${NC}"
echo ""
echo -e "Этот ключ нужен для настройки клиентов (нод)."
echo -e "Сохрани его!"
echo ""
echo -e "IP панели в AWG сети: ${YELLOW}10.10.0.1${NC}"
echo ""
echo -e "Для добавления ноды используй:"
echo -e "${YELLOW}./add-peer.sh <имя> <публичный_ключ_ноды> <awg_ip>${NC}"
echo ""
echo -e "Проверка статуса: ${YELLOW}awg show${NC}"
