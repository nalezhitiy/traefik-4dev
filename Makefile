.SILENT:
.NOTPARALLEL:

include mk/*.mk
include .env

ARCH := $(shell uname -m)
CERT_VOLUME=traefik-4dev_certs

MKCERT_VERSION=v1.4.4

ifeq ($(ARCH),arm64)
  MKCERT_ARCH=arm64
else
  MKCERT_ARCH=amd64
endif

# @echo $("docker network inspect traefik-4dev_network | grep Gateway")


## Full build (entry point)
build: volume certs images export-ca resolver-install export-ca
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

## create local resolver for BASE_DOMAIN
resolver-install:
	sudo mkdir -p /etc/resolver
	echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/$(BASE_DOMAIN) >/dev/null
	echo "Resolver installed: /etc/resolver/$(BASE_DOMAIN)"
.PHONY:	resolver-install

## remove local resolver for BASE_DOMAIN
resolver-remove:
	sudo rm -f /etc/resolver/$(BASE_DOMAIN)
	@echo "Resolver removed: /etc/resolver/$(BASE_DOMAIN)"
.PHONY: resolver-remove

## check dns resolution
check:
	@echo "→ checking DNS resolution"
	dscacheutil -q host -a name $(BASE_DOMAIN) | grep 127.0.0.1 || (echo "❌ DNS FAIL" && exit 1)
	@echo ""
	@echo "→ checking HTTPS endpoint"
	curl -s -o /dev/null -D - https://$(BASE_DOMAIN)/dashboard/

	@echo "✔ system ready"
.PHONY: check

## Start platform
start:
	@docker compose up -d
.PHONY: start


## Stop platform
stop:
	@docker compose stop
.PHONY: stop


## Restart platform
restart: stop start
.PHONY: restart


## Show logs
logs:
	@docker compose logs -f
.PHONY: logs


## Clean everything (containers, network, volumes)
clean: resolver-remove
	@docker compose down -v
	@docker volume rm $(CERT_VOLUME) >/dev/null 2>&1 || true
.PHONY: clean