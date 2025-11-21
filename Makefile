CONTAINER_NAME := supabase-db

DB_IP := $(shell docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CONTAINER_NAME))

DB_PASSWORD := $(shell grep -w POSTGRES_PASSWORD .env | cut -d '=' -f2)

migrate:
	@echo "$(DB_IP) - $(DB_PASSWORD)"
	supabase migration up --db-url "postgres://postgres:$(DB_PASSWORD)@$(DB_IP)/postgres?sslmode=disable" --debug
