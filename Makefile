.SILENT:
.NOTPARALLEL:

include mk/*.mk
include .env

OS := $(shell uname -s)
ARCH := $(shell uname -m)

CERT_VOLUME=traefik-4dev_certs
MKCERT_VERSION=v1.4.4


# =========================================================
# ARCH FIX
# =========================================================
ifeq ($(ARCH),arm64)
  MKCERT_ARCH=arm64
else ifeq ($(ARCH),aarch64)
  MKCERT_ARCH=arm64
else
  MKCERT_ARCH=amd64
endif


# =========================================================
# LOOPBACK (OS LAYER)
# =========================================================

ifeq ($(OS),Darwin)
LO_CHECK = ifconfig lo0
LO_ADD = sudo ifconfig lo0 alias $(TRAEFIK_IP)
LO_DEL = sudo ifconfig lo0 -alias $(TRAEFIK_IP)
endif

ifeq ($(OS),Linux)
LO_CHECK = ip addr show lo
LO_ADD = sudo ip addr add $(TRAEFIK_IP)/32 dev lo
LO_DEL = sudo ip addr del $(TRAEFIK_IP)/32 dev lo
endif


# =========================================================
# BUILD
# =========================================================

## Full build (entry point)
build: volume certs images export-ca resolver-install traefik-ip-install
	@echo "✔ traefik-4dev platform ready"
.PHONY: build


## Build docker images
images:
	@docker compose build
.PHONY: images


## Create certificate volume
volume:
	@docker volume inspect $(CERT_VOLUME) >/dev/null 2>&1 || \
	docker volume create $(CERT_VOLUME)
.PHONY: volume


## Generate TLS certificates (mkcert in container)
certs:
	@echo "→ generating mkcert wildcard cert"
	@docker run --rm \
		-v $(CERT_VOLUME):/certs \
		-e CAROOT=/certs \
		-e BASE_DOMAIN=$(BASE_DOMAIN) \
		alpine sh -c '\
			apk add --no-cache curl bash ca-certificates nss-tools && \
			curl -fL https://github.com/FiloSottile/mkcert/releases/download/$(MKCERT_VERSION)/mkcert-$(MKCERT_VERSION)-linux-$(MKCERT_ARCH) \
				-o /usr/local/bin/mkcert && \
			chmod +x /usr/local/bin/mkcert && \
			mkcert -install && \
			mkcert -cert-file /certs/cert.pem -key-file /certs/key.pem "$${BASE_DOMAIN}" "*.$${BASE_DOMAIN}" \
		'
.PHONY: certs


## Export root CA to host (browser trust)
export-ca:
	@docker run --rm \
		-v $(CERT_VOLUME):/certs \
		-v $(PWD)/data/certs:/out \
		alpine sh -c "cp -r /certs/* /out"
.PHONY: export-ca


# =========================================================
# DNS RESOLVER
# =========================================================

## create local resolver for BASE_DOMAIN
resolver-install:
ifeq ($(OS),Darwin)
	@sudo mkdir -p /etc/resolver
	@echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/$(BASE_DOMAIN) >/dev/null
	@echo "✔ resolver installed (macOS)"
else ifeq ($(OS),Linux)
	@echo "✔ Linux detected"
	@echo "IMPORTANT: ensure dnsmasq rule exists:"
	@echo "address=/$(BASE_DOMAIN)/$(TRAEFIK_IP)"
else
	@echo "Unsupported OS: $(OS)"
	exit 1
endif
.PHONY: resolver-install


## remove local resolver for BASE_DOMAIN
resolver-remove:
ifeq ($(OS),Darwin)
	@sudo rm -f /etc/resolver/$(BASE_DOMAIN)
	@echo "✔ resolver removed"
else ifeq ($(OS),Linux)
	@echo "✔ Linux: nothing to remove"
else
	@echo "Unsupported OS: $(OS)"
	exit 1
endif
.PHONY: resolver-remove


# =========================================================
# DNS CHECK (portable)
# =========================================================

## check dns + endpoint
check:
	@echo "→ DNS check (system resolver)"
	@dscacheutil -q host -a name $(BASE_DOMAIN) | grep $(TRAEFIK_IP) || true

	@echo ""
	@echo "→ HTTPS check"
	@curl -k -s -o /dev/null -D - https://$(BASE_DOMAIN)/dashboard/

	@echo "✔ system ready"
.PHONY: check


# =========================================================
# LOOPBACK IP
# =========================================================

## add traefik loopback ip
traefik-ip-install:
	@if $(LO_CHECK) 2>/dev/null | grep -q "$(TRAEFIK_IP)"; then \
		echo "✔ $(TRAEFIK_IP) already exists"; \
	else \
		$(LO_ADD); \
		echo "✔ added $(TRAEFIK_IP)"; \
	fi
.PHONY: traefik-ip-install


## remove traefik loopback ip
traefik-ip-remove:
	@if $(LO_CHECK) 2>/dev/null | grep -q "$(TRAEFIK_IP)"; then \
		$(LO_DEL); \
		echo "✔ removed $(TRAEFIK_IP)"; \
	else \
		echo "✔ not found"; \
	fi
.PHONY: traefik-ip-remove


# =========================================================
# RUNTIME
# =========================================================

## start platform
start: traefik-ip-install
	@docker compose up -d
.PHONY: start


## stop platform
stop:
	@docker compose stop
.PHONY: stop


## restart platform
restart: stop start
.PHONY: restart


## logs
logs:
	@docker compose logs -f
.PHONY: logs


# =========================================================
# CLEAN
# =========================================================

## clean everything
clean: traefik-ip-remove resolver-remove
	@docker compose down -v
	@docker volume rm $(CERT_VOLUME) >/dev/null 2>&1 || true
.PHONY: clean