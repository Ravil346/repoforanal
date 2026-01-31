#!/bin/bash
#
# Генератор конфига AWG для админа
# Запускать на панели
#

AWG_CONFIG_DIR="/etc/amnezia/amneziawg"
PANEL_PUBLIC_IP="91.208.184.247"
PANEL_AWG_PORT="51820"

# Обфускация (должны совпадать!)
JC=4
JMIN=40
JMAX=70
S1=0
S2=0
H1=1
H2=2
H3=3
H4=4

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Генерация конфига для админа${NC}"
echo -e "${GREEN}========================================${NC}"

# Получаем публичный ключ сервера
if [[ ! -f "$AWG_CONFIG_DIR/publickey" ]]; then
    echo -e "${RED}Сначала запусти panel-awg-setup.sh!${NC}"
    exit 1
fi

PANEL_PUBLIC_KEY=$(cat "$AWG_CONFIG_DIR/publickey")

# Генерируем ключи для админа
ADMIN_PRIVATE_KEY=$(awg genkey)
ADMIN_PUBLIC_KEY=$(echo "$ADMIN_PRIVATE_KEY" | awg pubkey)

# Создаём конфиг для админа
ADMIN_CONFIG="admin-awg.conf"

cat > "$ADMIN_CONFIG" << EOF
[Interface]
Address = 10.10.0.100/32
PrivateKey = $ADMIN_PRIVATE_KEY
DNS = 1.1.1.1

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

[Peer]
# Panel Server
PublicKey = $PANEL_PUBLIC_KEY
Endpoint = ${PANEL_PUBLIC_IP}:${PANEL_AWG_PORT}
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF

echo -e "\n${GREEN}Конфиг создан: $ADMIN_CONFIG${NC}"
echo ""
echo -e "Публичный ключ админа (для добавления на сервер):"
echo -e "${YELLOW}$ADMIN_PUBLIC_KEY${NC}"
echo ""
echo -e "${RED}Следующие шаги:${NC}"
echo ""
echo -e "1. Добавь админа на сервер:"
echo -e "   ${YELLOW}./add-peer.sh admin $ADMIN_PUBLIC_KEY 10.10.0.100${NC}"
echo ""
echo -e "2. Скопируй файл ${YELLOW}$ADMIN_CONFIG${NC} на свой компьютер"
echo ""
echo -e "3. Установи AmneziaVPN клиент:"
echo -e "   https://amnezia.org/downloads"
echo ""
echo -e "4. Импортируй конфиг в AmneziaVPN"
echo ""
echo -e "5. После подключения панель будет доступна по адресу:"
echo -e "   ${YELLOW}https://10.10.0.1${NC} или ${YELLOW}http://10.10.0.1:3000${NC}"
echo ""

# Показываем QR код если qrencode установлен
if command -v qrencode &> /dev/null; then
    echo -e "QR код для импорта:"
    qrencode -t ansiutf8 < "$ADMIN_CONFIG"
else
    echo -e "Для QR кода установи: ${YELLOW}apt install qrencode${NC}"
fi
