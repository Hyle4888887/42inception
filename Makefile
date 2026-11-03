COMPOSE = docker compose -f srcs/docker-compose.yml
DATA = /home/mpoirier/data

all:
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	$(COMPOSE) up --build -d

down:
	$(COMPOSE) down

clean: down
	docker system prune -af

fclean: clean
	docker volume rm -f $$(docker volume ls -q) 2>/dev/null || true
	sudo rm -rf $(DATA)

re: fclean all

.PHONY: all down clean fclean re