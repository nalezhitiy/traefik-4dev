# traefik-4dev

Локальна платформа для розробки на базі Traefik, Docker, dnsmasq та mkcert.

Основні можливості:

* wildcard домени (`*.dev.test`)
* HTTPS для локальних сервісів
* автоматична генерація TLS сертифікатів
* локальний DNS
* автоматична маршрутизація через Traefik
* підключення будь-яких Docker-сервісів через labels

---

# Вимоги

## Операційна система

Підтримуються Unix-подібні системи:

* macOS
* Ubuntu
* Debian
* Linux дистрибутиви з Docker Engine

Windows офіційно не підтримується.

## Docker

Мінімально рекомендовані версії:

```bash
Docker Engine >= 24
Docker Compose Plugin >= 2.20
```

Перевірити:

```bash
docker --version
docker compose version
```

## Make

```bash
make --version
```

---

# Team Onboarding

Підготовка нового середовища займає декілька хвилин.

### 1. Створити локальний конфіг

```bash
cp .env.example .env
```

### 2. Відредагувати домен

Наприклад:

```env
BASE_DOMAIN=dev.test
```

Можна використовувати будь-який локальний домен:

```env
BASE_DOMAIN=dev.test
BASE_DOMAIN=dev.loc
BASE_DOMAIN=my-project.test
BASE_DOMAIN=company.test
```

### 3. Зібрати платформу

```bash
make build
```

Команда автоматично:

* створить volume для сертифікатів
* згенерує Root CA
* згенерує wildcard TLS сертифікат
* експортує сертифікати на хост
* встановить локальний DNS resolver (перевірити `scutil --dns`)
* збере Docker образи

### 4. Додати Root CA в довірені сертифікати ОС

Після збірки буде створено файл:

```text
./data/certs/rootCA.pem
```

Необхідно додати його до довірених кореневих сертифікатів операційної системи.

Інструкції залежать від ОС:

* macOS — Keychain Access
* Ubuntu — update-ca-certificates
* Debian — update-ca-certificates

Без цього браузер буде показувати:

```text
NET::ERR_CERT_AUTHORITY_INVALID
```

### 5. Запустити платформу

```bash
make start
```

### 6. Відкрити браузер

```text
https://${BASE_DOMAIN}
```

Наприклад:

```text
https://dev.test
```

---

# Як працює маршрутизація

При відкритті:

```text
https://api.dev.test
```

відбувається наступний ланцюжок:

```text
Браузер
    │
    ▼
Resolver ОС
(/etc/resolver/dev.test)
    │
    ▼
127.0.0.1
    │
    ▼
dnsmasq
    │
    ▼
127.0.0.1
    │
    ▼
Traefik
    │
    ▼
Docker сервіс
```

---

## Resolver ОС

Під час виконання:

```bash
make resolver-install
```

створюється файл:

```text
/etc/resolver/${BASE_DOMAIN}
```

Наприклад:

```text
/etc/resolver/dev.test
```

з вмістом:

```text
nameserver 127.0.0.1
```

Це означає:

> Для всіх доменів *.dev.test використовувати локальний DNS сервер.

---

## dnsmasq

Конфігурація:

```conf
address=/.dev.test/127.0.0.1
```

Усі домени:

```text
dev.test
api.dev.test
admin.dev.test
dashboard.dev.test
```

резолвляться в:

```text
127.0.0.1
```

---

## Traefik

Traefik слухає порти:

```text
80
443
```

і маршрутизує запити відповідно до Docker labels.

Приклад https:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.api.rule=Host(`api.dev.test`)
  - traefik.http.routers.api.entrypoints=websecure
```
Приклад http:
```yaml
labels:
  - traefik.http.routers.api.rule=Host(`api.dev.test`)
  - traefik.http.routers.api.entrypoints=web
---
```

Приклад http and https:
```yaml

labels:
  - traefik.http.routers.api.rule=Host(`api.dev.test`)
  - traefik.http.routers.api.entrypoints=web,websecure
```
або 
```yaml
labels:
  - traefik.enable=true

  # HTTP
  - traefik.http.routers.api-http.rule=Host(`api.dev.test`)
  - traefik.http.routers.api-http.entrypoints=web

  # HTTPS
  - traefik.http.routers.api-https.rule=Host(`api.dev.test`)
  - traefik.http.routers.api-https.entrypoints=websecure
  - traefik.http.routers.api-https.tls=true

```

# Підключення власного сервісу

Приклад Docker Compose:

```yaml
services:
  api:
    image: my-api

    labels:
      - traefik.enable=true

      - traefik.http.routers.api.rule=Host(`api.dev.test`)
      - traefik.http.routers.api.entrypoints=websecure

      - traefik.http.services.api.loadbalancer.server.port=8080

    networks:
      - traefik-4dev_network

networks:
  traefik-4dev_network:
    external: true
```

Після запуску сервіс буде доступний:

```text
https://api.dev.test
```

## Приклад Traefik для MinIO (2 порти)
```yaml
services:
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"

    environment:
      MINIO_ROOT_USER: minio
      MINIO_ROOT_PASSWORD: minio123

    networks:
      - traefik-4dev_network

    labels:
      - traefik.enable=true

      # =========================
      # S3 API (port 9000)
      # =========================
      - traefik.http.routers.minio-api.rule=Host(`s3.dev.test`)
      - traefik.http.routers.minio-api.entrypoints=websecure
      - traefik.http.routers.minio-api.tls=true
      - traefik.http.services.minio-api.loadbalancer.server.port=9000

      # =========================
      # Console (port 9001)
      # =========================
      - traefik.http.routers.minio-console.rule=Host(`minio.dev.test`)
      - traefik.http.routers.minio-console.entrypoints=websecure
      - traefik.http.routers.minio-console.tls=true
      - traefik.http.services.minio-console.loadbalancer.server.port=9001

networks:
  traefik-4dev_network:
    external: true
```

---

# Основні команди

Повна збірка

```bash
make build
```

---

Запуск

```bash
make start
```

---

Зупинка

```bash
make stop
```

---

Перезапуск

```bash
make restart
```

---

Логи

```bash
make logs
```

---

Повне очищення

```bash
make clean
```

Видаляє:

* контейнери
* мережі
* volume із сертифікатами
* локальний resolver

---

# Діагностика

## Перевірка DNS

```bash
make check
```

Очікуваний результат:

```text
→ checking DNS resolution
ip_address: 127.0.0.1

→ checking HTTPS endpoint
HTTP/2 200 
content-security-policy: frame-src 'self' https://traefik.io https://*.traefik.io;
content-type: text/html; charset=utf-8
content-length: 689
date: Tue, 09 Jun 2026 16:54:50 GMT

✔ system ready
```

---

## Перевірка TLS

```bash
openssl s_client -connect ${BASE_DOMAIN}:443 -servername ${BASE_DOMAIN}
```

Сертифікат повинен бути випущений:

```text
mkcert development CA
```

Якщо бачите:

```text
TRAEFIK DEFAULT CERT
```

значить Traefik не завантажив ваш TLS сертифікат.

---

# Важливо

Ця платформа призначена виключно для локальної розробки.

Не використовуйте згенеровані сертифікати або Root CA у production середовищі.
