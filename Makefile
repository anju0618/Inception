NAME		= inception
LOGIN		= amakino
DATA_DIR	= /home/$(LOGIN)/data
COMPOSE_FILE	= srcs/docker-compose.yml
ENV_FILE	= srcs/.env
COMPOSE		= docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE)

.PHONY: all up build prepare down stop start restart logs ps clean fclean re

all: up

up: prepare
	$(COMPOSE) up --build -d

build: prepare
	$(COMPOSE) build

prepare:
	mkdir -p $(DATA_DIR)/wordpress
	mkdir -p $(DATA_DIR)/mariadb
	mkdir -p $(DATA_DIR)/backups

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean: down
	$(COMPOSE) down --rmi local --volumes --remove-orphans

fclean: clean
	sudo rm -rf $(DATA_DIR)/wordpress/* $(DATA_DIR)/mariadb/* $(DATA_DIR)/backups/*

re: fclean all
