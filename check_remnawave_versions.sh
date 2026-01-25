#!/bin/bash
# check_remnawave_versions.sh
# Скрипт для проверки реальных версий RemnaWave компонентов

echo "=== RemnaWave Version Check ==="
echo "Date: $(date)"
echo ""

# Проверяем панель (backend)
echo "--- PANEL (Backend) ---"
if docker ps --format '{{.Names}}' | grep -q remnawave; then
    CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^remnawave$|remnawave-backend')
    if [ -n "$CONTAINER" ]; then
        echo "Container: $CONTAINER"
        
        # Image ID и тег
        IMAGE_INFO=$(docker inspect --format='Image: {{.Config.Image}}
Created: {{.Created}}
Image ID: {{.Image}}' "$CONTAINER")
        echo "$IMAGE_INFO"
        
        # Реальная версия из labels (если есть)
        VERSION=$(docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' "$CONTAINER" 2>/dev/null)
        [ -n "$VERSION" ] && echo "Version Label: $VERSION"
        
        # Когда был создан контейнер
        STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER")
        echo "Started: $STARTED"
    fi
else
    echo "Panel container not found"
fi

echo ""

# Проверяем ноду
echo "--- NODE ---"
if docker ps --format '{{.Names}}' | grep -q remnanode; then
    CONTAINER="remnanode"
    echo "Container: $CONTAINER"
    
    IMAGE_INFO=$(docker inspect --format='Image: {{.Config.Image}}
Created: {{.Created}}
Image ID: {{.Image}}' "$CONTAINER")
    echo "$IMAGE_INFO"
    
    VERSION=$(docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' "$CONTAINER" 2>/dev/null)
    [ -n "$VERSION" ] && echo "Version Label: $VERSION"
    
    STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER")
    echo "Started: $STARTED"
else
    echo "Node container not found"
fi

echo ""

# Проверяем subscription page
echo "--- SUBSCRIPTION PAGE ---"
if docker ps --format '{{.Names}}' | grep -q subscription; then
    CONTAINER=$(docker ps --format '{{.Names}}' | grep subscription)
    echo "Container: $CONTAINER"
    
    IMAGE_INFO=$(docker inspect --format='Image: {{.Config.Image}}
Created: {{.Created}}
Image ID: {{.Image}}' "$CONTAINER")
    echo "$IMAGE_INFO"
    
    VERSION=$(docker inspect --format='{{index .Config.Labels "org.opencontainers.image.version"}}' "$CONTAINER" 2>/dev/null)
    [ -n "$VERSION" ] && echo "Version Label: $VERSION"
else
    echo "Subscription page container not found"
fi

echo ""
echo "--- LOCAL IMAGES ---"
docker images | grep -E "remnawave|remnanode" | awk '{print $1, $2, $3, $4, $5}'

echo ""
echo "=== End of check ==="