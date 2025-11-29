.PHONY: migration-deploy migration-new migration-down

# ----------------------------------------------------
# Configuration
# ----------------------------------------------------
ENV_FILE        := .env
CONTAINER_NAME  := supabase-db

# ----------------------------------------------------
# Helpers
# ----------------------------------------------------

DB_IP = $(shell docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CONTAINER_NAME) 2>/dev/null)
DB_PASSWORD = $(shell awk -F '=' '/^POSTGRES_PASSWORD=/ {print $$2}' $(ENV_FILE))
DB_URL = postgres://postgres:$(DB_PASSWORD)@$(DB_IP)/postgres?sslmode=disable

# ----------------------------------------------------
# Validations
# ----------------------------------------------------
check-env:
        @if [ ! -f "$(ENV_FILE)" ]; then \
                echo "[ERROR] $(ENV_FILE) file couldn't found"; \
                exit 1; \
        fi
        @if [ -z "$(DB_PASSWORD)" ]; then \
                echo "[ERROR] POSTGRES_PASSWORD couldn't found in the $(ENV_FILE) file"; \
                exit 1; \
        fi

check-ip:
        @if [ -z "$(DB_IP)" ]; then \
                echo "[ERROR] Couldn't got the container IP address"; \
                exit 1; \
        fi

# ----------------------------------------------------
# Targets
# ---------------------------------------------------
#
migration-deploy: check-env check-ip
        @supabase db push --db-url "$(DB_URL)" --debug

migration-down: check-env check-ip
        @supabase migration down --db-url "$(DB_URL)" --debug

migration-new: check-env check-ip
        @if [ -z "$(NAME)" ]; then \
            echo "ERROR: You must specify a migration name."; \
            exit 1; \
        fi
        @echo "Executing: supabase migration new $(NAME)"
        @supabase migration new $(NAME)  --debug