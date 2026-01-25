import subprocess

secret_key = input("Вставь SECRET_KEY из панели: ").strip()

compose = f"""services:
    remnanode:
        container_name: remnanode
        hostname: remnanode
        image: remnawave/node:latest
        network_mode: host
        restart: always
        ulimits:
            nofile:
                soft: 1048576
                hard: 1048576
        environment:
            - NODE_PORT=47891
            - SECRET_KEY="{secret_key}"
"""

print("\n" + "="*50)
print("Готовый docker-compose.yml:")
print("="*50 + "\n")
print(compose)

# Копируем в буфер обмена Windows (требует 'clip' в Windows 10/11, всегда есть)
try:
    process = subprocess.Popen(
        ['clip'],
        stdin=subprocess.PIPE, close_fds=True)
    process.communicate(input=compose.encode('utf-8'))
    print("\nКомпоз успешно скопирован в буфер обмена!")
except Exception as e:
    print(f"\nОшибка копирования в буфер обмена: {e}")