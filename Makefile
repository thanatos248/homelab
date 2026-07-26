STACKS := immich adguardhome vaultwarden karakeep searxng beszel
DC := docker compose -f

.PHONY: up down pull restart ps logs scan

up:
	@for s in $(STACKS); do echo ">> $$s"; $(DC) $$s/docker-compose.yml up -d; done

down:
	@for s in $(STACKS); do echo ">> $$s"; $(DC) $$s/docker-compose.yml down; done

pull:
	@for s in $(STACKS); do echo ">> $$s"; $(DC) $$s/docker-compose.yml pull; done

restart: down up

ps:
	@for s in $(STACKS); do echo "== $$s =="; $(DC) $$s/docker-compose.yml ps; done

logs:
	$(DC) $(SVC)/docker-compose.yml logs -f

scan:
	gitleaks detect --no-banner --source .
