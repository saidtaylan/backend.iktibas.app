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
		echo "[ERROR] $(ENV_FILE) bulunamadı."; \
		exit 1; \
	fi
	@if [ -z "$(DB_PASSWORD)" ]; then \
		echo "[ERROR] POSTGRES_PASSWORD değeri $(ENV_FILE) içinde bulunamadı."; \
		exit 1; \
	fi

check-ip:
	@if [ -z "$(DB_IP)" ]; then \
		echo "[ERROR] Container IP alınamadı."; \
		exit 1; \
	fi

# ----------------------------------------------------
# Targets
# ----------------------------------------------------
migrate: check-env check-ip
	@echo "[INFO] Container IP     : $(DB_IP)"
	@echo "[INFO] DB Password      : ******"
	@supabase migration up --db-url "$(DB_URL)" --debug

