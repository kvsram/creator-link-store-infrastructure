SHELL := /usr/bin/env bash
COMPOSE := docker compose -f local/docker-compose.yml

.PHONY: bootstrap doctor up smoke logs config down

bootstrap:
	./scripts/bootstrap-local.sh

doctor:
	./scripts/doctor.sh

up: doctor
	$(COMPOSE) up -d --build

smoke:
	./scripts/smoke-test.sh

logs:
	$(COMPOSE) logs -f --tail=200

config:
	$(COMPOSE) config --no-interpolate

down:
	$(COMPOSE) down
