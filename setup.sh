#!/bin/bash
# setup.sh — A lightning-fast WordPress Dev Environment in 60 seconds for rapid plugin and theme prototyping
# Cross-platform: Linux/macOS/WSL/Git Bash
# Usage: ./setup.sh [project-name]
# gl0bal01 - WpQuickDev
set -euo pipefail

# Color output functions
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[34m$1\033[0m"; }

PROJECT_NAME="${1:-wordpress-dev}"

# Validate PROJECT_NAME (allow letters, digits, hyphens, underscores only)
if ! echo "$PROJECT_NAME" | grep -Eq '^[A-Za-z0-9_-]+$'; then
    red "❌ Invalid project name: '$PROJECT_NAME'"
    echo "Use only letters, numbers, hyphens, and underscores."
    exit 1
fi

echo "$(blue "🚀 Creating WordPress Development Environment: $PROJECT_NAME")"

# Cleanup on interrupt before .env is written
SETUP_COMPLETE=0
cleanup_on_exit() {
    if [ "$SETUP_COMPLETE" -eq 0 ] && [ -n "${PROJECT_DIR:-}" ] && [ -d "$PROJECT_DIR" ] && [ ! -f "$PROJECT_DIR/.env" ]; then
        red "⚠️  Setup interrupted — removing partial project directory: $PROJECT_DIR"
        rm -rf "$PROJECT_DIR"
    fi
}
trap cleanup_on_exit EXIT INT TERM

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    fi

    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi

    if ! command -v make >/dev/null 2>&1; then
        missing_deps+=("make")
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        red "❌ Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        exit 1
    fi

    green "✅ All dependencies found"
}

# Detect user/group IDs (kept in .env for reference)
detect_user_ids() {
    if command -v id >/dev/null 2>&1; then
        HOST_UID=$(id -u)
        HOST_GID=$(id -g)
    else
        HOST_UID=1000
        HOST_GID=1000
    fi
}

check_dependencies
detect_user_ids

mkdir -p "$PROJECT_NAME"
PROJECT_DIR="$(cd "$PROJECT_NAME" && pwd)"
cd "$PROJECT_DIR"

############################################
#  .env + .env.example
############################################
if [ ! -f .env ]; then
  cat > .env << ENV_EOF
# -------- Core --------
COMPOSE_PROJECT_NAME=$PROJECT_NAME
PROJECT_NAME=$PROJECT_NAME

# Ports (change here if needed)
WP_PORT=8080
PMA_PORT=8081
MAILPIT_HTTP_PORT=8025
MAILPIT_SMTP_PORT=1025

# URLs / Timezone
# NOTE: If you change WP_PORT, update WP_URL below
WP_URL=http://localhost:8080
TZ=Europe/Paris

# PHP Version (supported: 8.1, 8.2, 8.3, 8.4, or latest)
PHP_VERSION=8.4

# Upload and Memory Limits
PHP_UPLOAD_MAX_FILESIZE=128M
PHP_POST_MAX_SIZE=128M
PHP_MEMORY_LIMIT=512M
PHP_MAX_INPUT_VARS=2000
PMA_UPLOAD_LIMIT=128M

# Database
DB_NAME=wordpress
DB_USER=wordpress
DB_PASSWORD=wordpress_secure_$(openssl rand -hex 8)
DB_ROOT_PASSWORD=root_secure_$(openssl rand -hex 8)

# Host user mapping (for reference)
HOST_UID=$HOST_UID
HOST_GID=$HOST_GID

# WordPress Config
WP_DEBUG=true
WP_DEBUG_LOG=true
WP_DEBUG_DISPLAY=false
DISALLOW_FILE_EDIT=true
DISABLE_WP_CRON=true
ENV_EOF
  green "✅ Created .env with secure random passwords"
else
  yellow "⚠️  .env already exists, skipping creation"
fi

# Always provide an example for teammates
cp -f .env .env.example
# Remove sensitive data from example (key-based replacement: works regardless of value pattern)
sed -i.bak \
    -e 's|^\(DB_PASSWORD=\).*|\1your_secure_password_here|' \
    -e 's|^\(DB_ROOT_PASSWORD=\).*|\1your_secure_root_password_here|' \
    .env.example && rm -f .env.example.bak

############################################
#  docker-compose.yml  (persistent wpcli + exec)
############################################
cat > docker-compose.yml << 'DOCKER_EOF'
services:
  wordpress:
    image: "wordpress:php${PHP_VERSION:-8.4}"
    ports:
      - "${WP_PORT:-8080}:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${DB_USER:-wordpress}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD:-wordpress}
      WORDPRESS_DB_NAME: ${DB_NAME:-wordpress}
      WORDPRESS_DEBUG: ${WP_DEBUG:-true}
      # PHP Configuration via environment
      PHP_UPLOAD_MAX_FILESIZE: ${PHP_UPLOAD_MAX_FILESIZE:-128M}
      PHP_POST_MAX_SIZE: ${PHP_POST_MAX_SIZE:-128M}
      PHP_MEMORY_LIMIT: ${PHP_MEMORY_LIMIT:-512M}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_DEBUG_LOG', ${WP_DEBUG_LOG:-true});
        define('WP_DEBUG_DISPLAY', ${WP_DEBUG_DISPLAY:-false});
        define('DISALLOW_FILE_EDIT', ${DISALLOW_FILE_EDIT:-true});
        define('DISABLE_WP_CRON', ${DISABLE_WP_CRON:-true});
        define('WP_MEMORY_LIMIT', '256M');
        define('WP_MAX_MEMORY_LIMIT', '512M');
        // Security headers
        define('FORCE_SSL_ADMIN', false);
        // Optional Mailpit (profile: dev)
        // define('SMTP_HOST', 'mailpit');
        // define('SMTP_PORT', ${MAILPIT_SMTP_PORT:-1025});
    volumes:
      - ./wordpress:/var/www/html
      - ./plugins:/var/www/html/wp-content/plugins
      - ./themes:/var/www/html/wp-content/themes
      - ./uploads:/var/www/html/wp-content/uploads
      - ./backups:/backups
      - ./.docker/php/php.ini:/usr/local/etc/php/conf.d/z-dev-overrides.ini:ro
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - wp-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  db:
    image: mariadb:11
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:-root}
      MYSQL_DATABASE: ${DB_NAME:-wordpress}
      MYSQL_USER: ${DB_USER:-wordpress}
      MYSQL_PASSWORD: ${DB_PASSWORD:-wordpress}
      TZ: ${TZ:-UTC}
      MARIADB_AUTO_UPGRADE: 1
      MARIADB_DISABLE_UPGRADE_BACKUP: 1
    command: >
      --character-set-server=utf8mb4
      --collation-server=utf8mb4_unicode_520_ci
      --innodb-buffer-pool-size=128M
      --innodb-log-file-size=64M
      --max_allowed_packet=64M
      --general-log=0
      --slow-query-log=1
      --slow-query-log-file=/var/log/mysql/slow.log
      --long_query_time=2
    volumes:
      - db_data:/var/lib/mysql
      - ./backups:/backups
      - ./.docker/mysql-init:/docker-entrypoint-initdb.d:ro
      - ./.docker/mysql-logs:/var/log/mysql
    healthcheck:
      test: ["CMD-SHELL", "healthcheck.sh --connect --innodb_initialized || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 40s
    restart: unless-stopped
    networks:
      - wp-network

  phpmyadmin:
    image: phpmyadmin:latest
    ports:
      - "${PMA_PORT:-8081}:80"
    environment:
      PMA_HOST: db
      PMA_USER: ${DB_USER:-wordpress}
      PMA_PASSWORD: ${DB_PASSWORD:-wordpress}
      UPLOAD_LIMIT: ${PMA_UPLOAD_LIMIT:-128M}
      MEMORY_LIMIT: 256M
      MAX_EXECUTION_TIME: 300
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - wp-network

  # Persistent wpcli container (no more "Creating 2/2" spam)
  wpcli:
    image: "wordpress:cli-php${PHP_VERSION:-8.4}"
    working_dir: /var/www/html
    command: tail -f /dev/null
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${DB_USER:-wordpress}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD:-wordpress}
      WORDPRESS_DB_NAME: ${DB_NAME:-wordpress}
      WP_CLI_PACKAGES_DIR: /tmp/.wp-cli/packages
      WP_CLI_CACHE_DIR: /tmp/.wp-cli/cache
      WP_CLI_CONFIG_PATH: /tmp/.wp-cli/config.yml
      TZ: ${TZ:-UTC}
      PAGER: less
    # Run as www-data (same as wordpress container)
    user: "33:33"
    volumes:
      - ./wordpress:/var/www/html
      - ./plugins:/var/www/html/wp-content/plugins
      - ./themes:/var/www/html/wp-content/themes
      - ./uploads:/var/www/html/wp-content/uploads
      - ./backups:/backups
    depends_on:
      db:
        condition: service_healthy
      wordpress:
        condition: service_started
    networks:
      - wp-network

  mailpit:
    image: axllent/mailpit:latest
    ports:
      - "${MAILPIT_HTTP_PORT:-8025}:8025"
      - "${MAILPIT_SMTP_PORT:-1025}:1025"
    environment:
      MP_SMTP_AUTH_ACCEPT_ANY: 1
      MP_SMTP_AUTH_ALLOW_INSECURE: 1
    restart: unless-stopped
    networks:
      - wp-network

volumes:
  db_data:
    driver: local

networks:
  wp-network:
    driver: bridge
DOCKER_EOF

############################################
#  Makefile (with literal tabs + containerized backup/restore + plugin git management)
############################################
cat > Makefile << 'MAKEFILE_EOF'
# WordPress Development Environment
.DEFAULT_GOAL := help
.PHONY: \
	help up down install clean shell db-shell logs \
	plugin theme backup restore db-import list-backups fix-permissions \
	wait-db wp sr cron-run phpinfo test health restart \
	plugin-repo plugin-clone plugin-list theme-repo theme-clone

# Stop "make[1]: on entre/quitte le répertoire ..." messages
MAKEFLAGS += --no-print-directory

# Load environment variables
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Smart Docker Compose detection (handles all versions)
DOCKER_COMPOSE := $(shell \
	if docker-compose --version >/dev/null 2>&1; then \
		echo "docker-compose"; \
	elif docker compose version >/dev/null 2>&1; then \
		echo "docker compose"; \
	else \
		echo "docker-compose"; \
	fi)

# Exec into always-on wpcli container (no more "Creating ..." spam)
RUN_WP := $(DOCKER_COMPOSE) exec -T wpcli wp
DB_EXEC := $(DOCKER_COMPOSE) exec -T db

help: ## Show this help
	@echo "WordPress Development Environment"
	@echo "================================="
	@grep -h -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## Start containers
	@echo "🚀 Starting containers..."
	@$(DOCKER_COMPOSE) up -d
	@echo "⏳ Waiting for services to be healthy..."
	@$(MAKE) wait-db
	@$(MAKE) health
	@echo "✅ Services are ready!"
	@echo "🌐 WordPress: $${WP_URL:-http://localhost:8080}"
	@echo "🗄️  phpMyAdmin: http://localhost:$${PMA_PORT:-8081}"

down: ## Stop containers
	@$(DOCKER_COMPOSE) down

restart: ## Restart containers
	@$(MAKE) down
	@$(MAKE) up

wait-db: ## Wait for database to be ready
	@echo "⏳ Waiting for database..."
	@timeout=60; 	while ! $(DOCKER_COMPOSE) exec -T db mariadb -u"$${DB_USER:-wordpress}" -p"$${DB_PASSWORD:-wordpress}" -e "SELECT 1" "$${DB_NAME:-wordpress}" >/dev/null 2>&1; do 		timeout=$$((timeout - 1)); 		if [ $$timeout -eq 0 ]; then 			echo "❌ Database failed to start within 60 seconds"; 			$(DOCKER_COMPOSE) logs db | tail -20; 			exit 1; 		fi; 		sleep 1; 	 done
	@echo "✅ Database is ready"

health: ## Check service health
	@echo "🏥 Checking service health..."
	@$(DOCKER_COMPOSE) ps
	@echo "Database connection test:"
	@$(DB_EXEC) mariadb -u"$${DB_USER:-wordpress}" -p"$${DB_PASSWORD:-wordpress}" -e "SELECT 'DB OK' as status, VERSION() as version;" "$${DB_NAME:-wordpress}" 2>/dev/null || echo "❌ Database connection failed"

install: up ## Download, configure and install WordPress
	@if [ -f wordpress/wp-config.php ]; then 		echo "⚠️  WordPress already installed (wordpress/wp-config.php exists)."; 		echo "   Run 'make clean' first to reinstall from scratch."; 		exit 1; 	fi
	@echo "📦 Installing WordPress..."
	@$(RUN_WP) core download --path=/var/www/html --skip-content
	@echo "🔧 Creating wp-config.php..."
	@$(RUN_WP) config create 		--dbname="$${DB_NAME:-wordpress}" 		--dbuser="$${DB_USER:-wordpress}" 		--dbpass="$${DB_PASSWORD:-wordpress}" 		--dbhost=db 		--skip-check
	@$(RUN_WP) config set WP_DEBUG "$${WP_DEBUG:-true}" --raw
	@$(RUN_WP) config set WP_DEBUG_LOG "$${WP_DEBUG_LOG:-true}" --raw
	@$(RUN_WP) config set WP_DEBUG_DISPLAY "$${WP_DEBUG_DISPLAY:-false}" --raw
	@$(RUN_WP) config set DISALLOW_FILE_EDIT "$${DISALLOW_FILE_EDIT:-true}" --raw
	@$(RUN_WP) config set DISABLE_WP_CRON "$${DISABLE_WP_CRON:-true}" --raw
	@echo "🔐 Installing WordPress with secure credentials..."
	@ADMIN_PASS="$$(openssl rand -base64 16 | tr -d '=' | head -c 16)"; 	ADMIN_EMAIL="admin@$$(echo $${WP_URL:-http://localhost:8080} | sed 's|https\?://||' | sed 's|:.*||').local"; 	$(RUN_WP) core install 		--url="$${WP_URL:-http://localhost:8080}" 		--title="$${PROJECT_NAME:-WordPress Dev} Site" 		--admin_user=admin 		--admin_password="$$ADMIN_PASS" 		--admin_email="$$ADMIN_EMAIL" 		--skip-email; 	echo ""; 	echo "✅ WordPress installed successfully!"; 	echo "🌐 URL: $${WP_URL:-http://localhost:8080}"; 	echo "👤 Username: admin"; 	echo "🔑 Password: $$ADMIN_PASS"; 	echo "📧 Email: $$ADMIN_EMAIL"
	@$(MAKE) fix-permissions

clean: ## Reset everything (removes all data!) — pass FORCE=1 for non-interactive
	@echo "⚠️  This will delete ALL data including database and uploads!"
	@if [ -n "$(FORCE)" ]; then 		confirm=y; 	else 		read -p "Are you sure? (y/N): " confirm; 	fi; 	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then 		$(DOCKER_COMPOSE) down -v; 		rm -rf wordpress plugins themes uploads .docker 2>/dev/null || true; 		echo "✅ Environment reset!"; 	else 		echo "❌ Operation cancelled"; 	fi

shell: ## Access WordPress container shell
	@$(DOCKER_COMPOSE) exec wordpress bash

db-shell: ## Access database container shell
	@$(DOCKER_COMPOSE) exec db bash

logs: ## Show logs (usage: make logs [service=wordpress])
	@if [ -n "$(service)" ]; then 		$(DOCKER_COMPOSE) logs -f $(service); 	else 		$(DOCKER_COMPOSE) logs -f; 	fi

fix-permissions: ## Fix file permissions for development
	@echo "🔧 Fixing permissions..."
	@mkdir -p wordpress plugins themes uploads backups .docker/mysql-logs
	@chmod 0700 backups 2>/dev/null || true
	@find wordpress plugins themes uploads -type d -exec chmod 0775 {} + 2>/dev/null || true
	@find wordpress plugins themes uploads -type f -exec chmod 0664 {} + 2>/dev/null || true
	@$(DOCKER_COMPOSE) exec -T wordpress bash -lc 		'install -d -m 0775 /var/www/html/wp-content/plugins /var/www/html/wp-content/themes /var/www/html/wp-content/uploads 2>/dev/null || true; 		 find /var/www/html -type d -exec chmod 0775 {} + 2>/dev/null || true; 		 find /var/www/html -type f -exec chmod 0664 {} + 2>/dev/null || true'
	@echo "✅ Permissions fixed"

plugin: fix-permissions ## Create plugin (usage: make plugin name=my-plugin)
	@if [ -z "$(name)" ]; then 		echo "❌ Usage: make plugin name=my-plugin"; 		exit 1; 	fi
	@mkdir -p plugins/$(name)
	@echo '<?php' > plugins/$(name)/$(name).php
	@echo '/**' >> plugins/$(name)/$(name).php
	@echo ' * Plugin Name: $(name)' >> plugins/$(name)/$(name).php
	@echo ' * Description: Custom plugin for development' >> plugins/$(name)/$(name).php
	@echo ' * Version: 1.0.0' >> plugins/$(name)/$(name).php
	@echo ' * Author: Dev Team' >> plugins/$(name)/$(name).php
	@echo ' */' >> plugins/$(name)/$(name).php
	@echo '' >> plugins/$(name)/$(name).php
	@echo 'if (!defined("ABSPATH")) exit;' >> plugins/$(name)/$(name).php
	@echo '' >> plugins/$(name)/$(name).php
	@echo '// Plugin initialization' >> plugins/$(name)/$(name).php
	@echo 'add_action("init", function() {' >> plugins/$(name)/$(name).php
	@echo '    // Your plugin code here' >> plugins/$(name)/$(name).php
	@echo '});' >> plugins/$(name)/$(name).php
	@$(RUN_WP) plugin activate $(name) 2>/dev/null || echo "⚠️  Plugin created but not activated"
	@echo "✅ Plugin created: plugins/$(name)/$(name).php"
	@echo "💡 Next step: make plugin-repo name=$(name) to initialize git repository"

plugin-repo: ## Initialize plugin as separate git repo (usage: make plugin-repo name=my-plugin)
	@if [ -z "$(name)" ]; then 		echo "❌ Usage: make plugin-repo name=my-plugin"; 		exit 1; 	fi
	@if [ ! -d "plugins/$(name)" ]; then 		echo "❌ Plugin directory plugins/$(name) doesn't exist. Run 'make plugin name=$(name)' first"; 		exit 1; 	fi
	@if [ -d "plugins/$(name)/.git" ]; then 		echo "⚠️  Git repository already exists for plugin: $(name)"; 		exit 0; 	fi
	@cd plugins/$(name) && 		git init && 		echo "# $(name)" > README.md && 		echo "" >> README.md && 		echo "WordPress plugin for development." >> README.md && 		echo "" >> README.md && 		echo "## Installation" >> README.md && 		echo "1. Copy this plugin to your WordPress plugins directory" >> README.md && 		echo "2. Activate the plugin through the WordPress admin" >> README.md && 		echo "" >> README.md && 		echo "## Development" >> README.md && 		echo "This plugin was created using the WordPress dev environment." >> README.md && 		echo "" >> README.md && 		git add . && 		git commit -m "Initial commit for $(name) plugin" && 		echo "✅ Git repository initialized for plugin: $(name)"
	@echo "💡 Next steps:"
	@echo "   cd plugins/$(name)"
	@echo "   git remote add origin https://github.com/username/$(name).git"
	@echo "   git push -u origin main"

plugin-clone: ## Clone existing plugin repo (usage: make plugin-clone repo=https://github.com/user/plugin.git [name=custom-name])
	@if [ -z "$(repo)" ]; then 		echo "❌ Usage: make plugin-clone repo=https://github.com/user/plugin.git [name=custom-name]"; 		exit 1; 	fi
	@PLUGIN_NAME="$(name)"; 	if [ -z "$$PLUGIN_NAME" ]; then 		PLUGIN_NAME=$$(basename "$(repo)" .git); 	fi; 	if [ -d "plugins/$$PLUGIN_NAME" ]; then 		echo "❌ Plugin directory plugins/$$PLUGIN_NAME already exists"; 		exit 1; 	fi; 	echo "📦 Cloning plugin repository..."; 	git clone "$(repo)" "plugins/$$PLUGIN_NAME" && 	echo "✅ Plugin cloned: plugins/$$PLUGIN_NAME"; 	if $(DOCKER_COMPOSE) ps wordpress | grep -q "Up"; then 		echo "🔄 Activating plugin..."; 		$(RUN_WP) plugin activate "$$PLUGIN_NAME" 2>/dev/null || echo "⚠️  Plugin cloned but not activated"; 	fi

plugin-list: ## List all plugins (local and git repos)
	@echo "📦 Local Plugins:"
	@echo "================"
	@if [ -d "plugins" ]; then 		for plugin in plugins/*/; do 			if [ -d "$$plugin" ]; then 				plugin_name=$$(basename "$$plugin"); 				if [ -d "$$plugin/.git" ]; then 					echo "🔗 $$plugin_name (git repo)"; 					cd "$$plugin" && git remote -v 2>/dev/null | head -1 | awk '{print "   " $$2}' || echo "   (no remote)"; 					cd - >/dev/null; 				else 					echo "📁 $$plugin_name (local only)"; 				fi; 			fi; 		done; 	else 		echo "No plugins directory found"; 	fi
	@echo ""
	@if $(DOCKER_COMPOSE) ps wordpress | grep -q "Up"; then 		echo "🔌 WordPress Plugin Status:"; 		echo "=========================="; 		$(RUN_WP) plugin list --format=table 2>/dev/null || echo "WordPress not ready"; 	fi

theme: fix-permissions ## Create theme (usage: make theme name=my-theme)
	@if [ -z "$(name)" ]; then 		echo "❌ Usage: make theme name=my-theme"; 		exit 1; 	fi
	@mkdir -p themes/$(name)
	@echo '/*' > themes/$(name)/style.css
	@echo 'Theme Name: $(name)' >> themes/$(name)/style.css
	@echo 'Description: Custom theme for development' >> themes/$(name)/style.css
	@echo 'Version: 1.0.0' >> themes/$(name)/style.css
	@echo 'Author: Dev Team' >> themes/$(name)/style.css
	@echo '*/' >> themes/$(name)/style.css
	@echo '<?php // functions.php' > themes/$(name)/functions.php
	@echo '<?php get_header(); ?>' > themes/$(name)/index.php
	@echo '<main><h1>Hello World from $(name)</h1></main>' >> themes/$(name)/index.php
	@echo '<?php get_footer(); ?>' >> themes/$(name)/index.php
	@$(RUN_WP) theme activate $(name) 2>/dev/null || echo "⚠️  Theme created but not activated"
	@echo "✅ Theme created: themes/$(name)/"
	@echo "💡 Next step: make theme-repo name=$(name) to initialize git repository"

theme-repo: ## Initialize theme as separate git repo (usage: make theme-repo name=my-theme)
	@if [ -z "$(name)" ]; then 		echo "❌ Usage: make theme-repo name=my-theme"; 		exit 1; 	fi
	@if [ ! -d "themes/$(name)" ]; then 		echo "❌ Theme directory themes/$(name) doesn't exist. Run 'make theme name=$(name)' first"; 		exit 1; 	fi
	@if [ -d "themes/$(name)/.git" ]; then 		echo "⚠️  Git repository already exists for theme: $(name)"; 		exit 0; 	fi
	@cd themes/$(name) && 		git init && 		echo "# $(name)" > README.md && 		echo "" >> README.md && 		echo "WordPress theme for development." >> README.md && 		echo "" >> README.md && 		echo "## Installation" >> README.md && 		echo "1. Copy this theme to your WordPress themes directory" >> README.md && 		echo "2. Activate the theme through the WordPress admin" >> README.md && 		echo "" >> README.md && 		git add . && 		git commit -m "Initial commit for $(name) theme" && 		echo "✅ Git repository initialized for theme: $(name)"
	@echo "💡 Next steps:"
	@echo "   cd themes/$(name)"
	@echo "   git remote add origin https://github.com/username/$(name).git"
	@echo "   git push -u origin main"

theme-clone: ## Clone existing theme repo (usage: make theme-clone repo=https://github.com/user/theme.git [name=custom-name])
	@if [ -z "$(repo)" ]; then 		echo "❌ Usage: make theme-clone repo=https://github.com/user/theme.git [name=custom-name]"; 		exit 1; 	fi
	@THEME_NAME="$(name)"; 	if [ -z "$$THEME_NAME" ]; then 		THEME_NAME=$$(basename "$(repo)" .git); 	fi; 	if [ -d "themes/$$THEME_NAME" ]; then 		echo "❌ Theme directory themes/$$THEME_NAME already exists"; 		exit 1; 	fi; 	echo "📦 Cloning theme repository..."; 	git clone "$(repo)" "themes/$$THEME_NAME" && 	echo "✅ Theme cloned: themes/$$THEME_NAME"; 	if $(DOCKER_COMPOSE) ps wordpress | grep -q "Up"; then 		echo "🔄 Activating theme..."; 		$(RUN_WP) theme activate "$$THEME_NAME" 2>/dev/null || echo "⚠️  Theme cloned but not activated"; 	fi

backup: ## Create database backup (runs fully inside DB container)
	@$(DB_EXEC) sh -lc '		set -e; 		mkdir -p /backups; 		FILE="/backups/backup-$$(date +%Y%m%d-%H%M%S).sql.gz"; 		echo "📦 Creating backup $$FILE..."; 		mariadb-dump 			-u"$$MYSQL_USER" 			-p"$$MYSQL_PASSWORD" 			--single-transaction 			--quick 			--routines 			--default-character-set=utf8mb4 			"$$MYSQL_DATABASE" 		| gzip > "$$FILE"; 		if [ -s "$$FILE" ]; then 			ls -lh "$$FILE"; 			chmod 0666 "$$FILE" || true; 			echo "✅ Backup created: $$FILE"; 		else 			echo "❌ Backup failed (empty file)"; 			exit 1; 		fi 	'

restore: ## Restore database (usage: make restore file=backup.sql[.gz])
	@if [ -z "$(file)" ]; then 		echo "❌ Usage: make restore file=<backup-file>"; 		echo "Available backups:"; 		ls -la backups/*.sql* 2>/dev/null | head -10 || echo "No backups found"; 		exit 1; 	fi
	@$(DB_EXEC) sh -lc '\
		set -e; \
		RF="$(file)"; \
		case "$$RF" in \
			/backups/*) PATH_IN="$$RF" ;; \
			/*)         PATH_IN="$$RF" ;; \
			backups/*)  PATH_IN="/backups/$${RF#backups/}" ;; \
			*)          PATH_IN="/backups/$$RF" ;; \
		esac; \
		if [ ! -f "$$PATH_IN" ]; then \
			echo "❌ Backup file not found in container: $$PATH_IN"; \
			exit 1; \
		fi; \
		echo "📦 Restoring from $$PATH_IN..."; \
		if echo "$$PATH_IN" | grep -q "\.gz$$"; then \
			gunzip -c "$$PATH_IN" | mariadb -u"$$MYSQL_USER" -p"$$MYSQL_PASSWORD" "$$MYSQL_DATABASE"; \
		else \
			mariadb -u"$$MYSQL_USER" -p"$$MYSQL_PASSWORD" "$$MYSQL_DATABASE" < "$$PATH_IN"; \
		fi; \
		echo "✅ Database restored from $$PATH_IN" \
	'

db-import: ## Import external database (usage: make db-import file=/path/to/database.sql[.gz])
	@if [ -z "$(file)" ]; then \
		echo "❌ Usage: make db-import file=/path/to/database.sql[.gz]"; \
		echo "Example: make db-import file=/home/user/mysite.sql.gz"; \
		exit 1; \
	fi
	@if [ ! -f "$(file)" ]; then \
		echo "❌ File not found: $(file)"; \
		exit 1; \
	fi
	@if ! $(DOCKER_COMPOSE) ps db | grep -q "Up" 2>/dev/null; then \
		echo "❌ Database container is not running. Please start it first:"; \
		echo "   make up"; \
		exit 1; \
	fi
	@echo "📦 Importing database from $(file)..."
	@FILENAME=$$(basename "$(file)"); \
	cp "$(file)" "backups/$$FILENAME" && \
	echo "✅ Copied to backups/$$FILENAME"; \
	$(MAKE) restore file="$$FILENAME"

list-backups: ## List available backups
	@echo "📁 Available backups:"
	@ls -lht backups/*.sql* 2>/dev/null | head -20 || echo "No backups found"

wp: ## Run WP-CLI command (usage: make wp cmd="plugin list")
	@if [ -z "$(cmd)" ]; then 		echo "❌ Usage: make wp cmd="command here""; 		exit 1; 	fi
	@$(RUN_WP) $(cmd)

sr: ## Search-replace URLs (usage: make sr old=http://old.com new=http://new.com)
	@if [ -z "$(old)" ] || [ -z "$(new)" ]; then 		echo "❌ Usage: make sr old=<old-url> new=<new-url>"; 		exit 1; 	fi
	@$(RUN_WP) search-replace "$(old)" "$(new)" --all-tables --skip-columns=guid

cron-run: ## Run WordPress cron events
	@$(RUN_WP) cron event run --due-now

test: ## Run basic tests
	@echo "🧪 Running basic tests..."
	@$(MAKE) health
	@$(RUN_WP) core version 2>/dev/null && echo "✅ WP-CLI working" || echo "❌ WP-CLI failed"

phpinfo: ## Create phpinfo file
	@echo "<?php phpinfo(); ?>" > wordpress/info.php
	@echo "✅ Created wordpress/info.php"
MAKEFILE_EOF

############################################
#  Improved PHP configuration
############################################
mkdir -p .docker/php .docker/mysql-init .docker/mysql-logs
cat > .docker/php/php.ini << 'PHP_EOF'
; Development PHP Configuration
; NOTE: PHP upload/memory limits are set via .env file
; The docker-compose.yml passes PHP_UPLOAD_MAX_FILESIZE, PHP_POST_MAX_SIZE, PHP_MEMORY_LIMIT
; Memory and execution
memory_limit = 512M
max_execution_time = 300
max_input_time = 300

; File uploads
upload_max_filesize = 128M
post_max_size = 128M
max_file_uploads = 50
max_input_vars = 2000

; Error reporting and logging
display_errors = On
display_startup_errors = On
log_errors = On
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
html_errors = On

; Session and timezone
session.gc_maxlifetime = 3600
; date.timezone is set via TZ env var from .env (passed by docker-compose)

; OPcache for development
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 256
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 0
opcache.validate_timestamps = 1

; Security (development settings)
expose_php = Off
allow_url_fopen = On
allow_url_include = Off

; Performance
realpath_cache_size = 4096K
realpath_cache_ttl = 600
PHP_EOF

############################################
#  .gitignore (updated for plugin development)
############################################
cat > .gitignore << 'GITIGNORE_EOF'
# WordPress core and content
wordpress/
uploads/

# Plugins (each should have their own repo — preserve directory via .gitkeep)
plugins/*
!plugins/.gitkeep

# Themes (each should have their own repo — preserve directory via .gitkeep)
themes/*
!themes/.gitkeep

# Database backups (contain sensitive data)
backups/

# Environment and secrets
.env

# Generated helper scripts (regenerated by setup.sh)
backup.sh
restore.sh
health-check.sh
plugin-status.sh

# System files
.DS_Store
Thumbs.db
*.log

# IDE files
.vscode/
.idea/
*.swp
*.swo
*~

# Docker volumes and temp
.docker/

# Backup temp files
*.tmp
*.sql.gz.tmp
GITIGNORE_EOF

############################################
#  README.md (updated with plugin development workflow)
############################################
cat > README.md << 'README_EOF'
# WordPress Development Environment

A rapid development environment for WordPress plugins and themes, designed for separate repository management.

## Quick Start
```bash
./setup.sh my-project
cd my-project
make up
make install
```

## Plugin Development Workflow

### Create a New Plugin
```bash
# Create plugin structure
make plugin name=my-awesome-plugin

# Initialize as git repository
make plugin-repo name=my-awesome-plugin

# Set up remote repository
cd plugins/my-awesome-plugin
git remote add origin https://github.com/username/my-awesome-plugin.git
git push -u origin main
```

### Clone Existing Plugin
```bash
# Clone from repository
make plugin-clone repo=https://github.com/username/existing-plugin.git

# Or clone with custom name
make plugin-clone repo=https://github.com/username/plugin.git name=custom-name
```

### Manage Plugins
```bash
# List all plugins (local and git status)
make plugin-list

# Activate/deactivate via WP-CLI
make wp cmd="plugin activate my-plugin"
make wp cmd="plugin deactivate my-plugin"
```

## Theme Development
```bash
# Create theme
make theme name=my-theme

# Initialize as git repository
make theme-repo name=my-theme

# Clone existing theme
make theme-clone repo=https://github.com/username/theme.git
```

## Database Management
```bash
# Create backup
make backup

# Restore from backup
make restore file=backup-20240116-143022.sql.gz

# Import external database (from anywhere on your system)
make db-import file=/path/to/database.sql.gz

# List available backups
make list-backups
```

## Development Tools
```bash
# Fix file permissions
make fix-permissions

# Access container shells
make shell     # WordPress container
make db-shell  # Database container

# View logs
make logs                    # All services
make logs service=wordpress  # Specific service

# Run WP-CLI commands
make wp cmd="option get siteurl"
make wp cmd="user list"

# Search-replace URLs
make sr old=http://old.local new=http://new.local
```

## Access URLs
- **WordPress**: http://localhost:8080
- **phpMyAdmin**: http://localhost:8081
- **Mailpit** (dev profile): http://localhost:8025

## Configuration

Edit the `.env` file to customize your environment:

### PHP Version
```bash
# Specify PHP version (8.1, 8.2, 8.3, 8.4)
PHP_VERSION=8.4
```

### Upload and Memory Limits
```bash
# Customize PHP limits
PHP_UPLOAD_MAX_FILESIZE=128M
PHP_POST_MAX_SIZE=128M
PHP_MEMORY_LIMIT=512M
PHP_MAX_INPUT_VARS=2000
PMA_UPLOAD_LIMIT=128M  # phpMyAdmin upload limit
```

### Ports
```bash
# Change if ports are already in use
WP_PORT=8080
PMA_PORT=8081
MAILPIT_HTTP_PORT=8025
```

### Database
```bash
# Auto-generated secure passwords
DB_NAME=wordpress
DB_USER=wordpress
DB_PASSWORD=wordpress_secure_[random]
DB_ROOT_PASSWORD=root_secure_[random]
```

After changing `.env`, restart the environment:
```bash
make restart
```

## File Structure
```
my-project/
├── plugins/           # Plugin development (ignored in git)
│   ├── my-plugin/     # Each plugin has its own git repo
│   └── another-plugin/
├── themes/            # Theme development (ignored in git)
├── uploads/           # WordPress uploads
├── backups/           # Database backups
├── wordpress/         # WordPress core (ignored in git)
└── .env              # Environment configuration
```

## Tips
- Each plugin/theme should be its own git repository
- Use `make plugin-list` to see git status of all plugins
- Backups are compressed and timestamped automatically
- File permissions are set to 0777 for cross-platform development
- Use `make health` to check if all services are running properly

## Troubleshooting
```bash
# Check service health
make health

# Restart containers
make restart

# View container status
docker compose ps

# Reset everything (⚠️ destroys all data)
make clean
```
README_EOF

############################################
#  backup.sh (optional helper; runs via DB container path)
############################################
cat > backup.sh << 'BACKUP_EOF'
#!/bin/bash
set -euo pipefail
[ -f .env ] && source .env || { echo "❌ .env not found"; exit 1; }
docker compose exec -T db sh -lc '
  set -e;
  mkdir -p /backups;
  FILE="/backups/backup-$(date +%Y%m%d-%H%M%S).sql.gz";
  echo "📦 Creating backup $FILE...";
  mariadb-dump -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" --single-transaction --quick --routines --default-character-set=utf8mb4 "$MYSQL_DATABASE" | gzip > "$FILE";
  [ -s "$FILE" ] || { echo "❌ Backup failed"; exit 1; }
  chmod 0666 "$FILE" || true;
  ls -lh "$FILE";
  echo "✅ Backup created: $FILE";
'
BACKUP_EOF

############################################
#  restore.sh (optional helper; uses /backups in container)
############################################
cat > restore.sh << 'RESTORE_EOF'
#!/bin/bash
set -euo pipefail
[ -f .env ] && source .env || { echo "❌ .env not found"; exit 1; }

if [ $# -eq 0 ]; then
  echo "Usage: $0 <backup.sql[.gz]>"
  ls -la backups/*.sql* 2>/dev/null | head -10 || echo "No backups found"
  exit 1
fi

FILE="$1"
case "$FILE" in
  /backups/*) PATH_IN="$FILE" ;;
  /*)         PATH_IN="$FILE" ;;
  backups/*)  PATH_IN="/backups/${FILE#backups/}" ;;
  *)          PATH_IN="/backups/$FILE" ;;
esac

export PATH_IN
docker compose exec -T -e PATH_IN db sh -lc '
  set -e
  [ -f "$PATH_IN" ] || { echo "❌ Backup file not found in container: $PATH_IN"; exit 1; }
  echo "📦 Restoring from $PATH_IN..."
  case "$PATH_IN" in
    *.gz)
      gunzip -c "$PATH_IN" | mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"
      ;;
    *)
      mariadb -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$PATH_IN"
      ;;
  esac
  echo "✅ Database restored from $PATH_IN"
'
RESTORE_EOF

############################################
#  Health check script
############################################
cat > health-check.sh << 'HEALTH_EOF'
#!/bin/bash
set -euo pipefail
ESC=$(printf '\033')
red()    { printf '%s[31m%s%s[0m\n' "$ESC" "$1" "$ESC"; }
green()  { printf '%s[32m%s%s[0m\n' "$ESC" "$1" "$ESC"; }
yellow() { printf '%s[33m%s%s[0m\n' "$ESC" "$1" "$ESC"; }
blue()   { printf '%s[34m%s%s[0m\n' "$ESC" "$1" "$ESC"; }

[ -f .env ] && source .env || { red "❌ .env file not found"; exit 1; }

blue "🏥 WordPress Development Environment Health Check"
echo "=================================================="

echo "🐳 Docker Status:"
if command -v docker >/dev/null 2>&1; then
  green "  ✅ Docker installed: $(docker --version)"
  if docker compose version >/dev/null 2>&1; then
    green "  ✅ Docker Compose available"
  else
    red "  ❌ Docker Compose not available"
  fi
else
  red "  ❌ Docker not installed"
fi
echo ""

echo "📦 Container Status:"
if docker compose ps >/dev/null 2>&1; then
  docker compose ps
else
  red "  ❌ Cannot check container status"
fi
echo ""

echo "🌐 Service Health:"
if curl -sf "${WP_URL}" >/dev/null 2>&1; then
  green "  ✅ WordPress accessible at ${WP_URL}"
else
  red "  ❌ WordPress not accessible at ${WP_URL}"
fi

if curl -sf "http://localhost:${PMA_PORT}" >/dev/null 2>&1; then
  green "  ✅ phpMyAdmin accessible at http://localhost:${PMA_PORT}"
else
  red "  ❌ phpMyAdmin not accessible at http://localhost:${PMA_PORT}"
fi

if docker compose exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1" "${DB_NAME}" >/dev/null 2>&1; then
  green "  ✅ Database connection working"
else
  red "  ❌ Database connection failed"
fi

if docker compose exec -T wpcli wp core version >/dev/null 2>&1; then
  WP_VERSION=$(docker compose exec -T wpcli wp core version 2>/dev/null || echo "Unknown")
  green "  ✅ WP-CLI working (WordPress: $WP_VERSION)"
else
  red "  ❌ WP-CLI not working"
fi
echo ""

echo "🔌 Plugin Development:"
if [ -d "plugins" ]; then
  PLUGIN_COUNT=$(find plugins -maxdepth 1 -type d | wc -l)
  PLUGIN_COUNT=$((PLUGIN_COUNT - 1))  # Exclude plugins directory itself
  GIT_PLUGINS=$(find plugins -maxdepth 2 -name ".git" -type d | wc -l)
  echo "  Plugins: $PLUGIN_COUNT total, $GIT_PLUGINS with git repositories"

  if [ $GIT_PLUGINS -gt 0 ]; then
    echo "  Git-managed plugins:"
    for plugin_dir in plugins/*/; do
      if [ -d "$plugin_dir/.git" ]; then
        plugin_name=$(basename "$plugin_dir")
        cd "$plugin_dir"
        if git remote -v >/dev/null 2>&1; then
          remote=$(git remote get-url origin 2>/dev/null || echo "no remote")
          echo "    📦 $plugin_name → $remote"
        else
          echo "    📁 $plugin_name (local git only)"
        fi
        cd - >/dev/null
      fi
    done
  fi
else
  echo "  No plugins directory found"
fi
echo ""

echo "💾 Storage Status:"
df -h . | tail -n1 | awk '{print "  Available space: " $4 " (" $5 " used)"}'
BACKUP_COUNT=$(ls -1 backups/*.sql* 2>/dev/null | wc -l || echo 0)
echo "  Backups available: $BACKUP_COUNT"
if [ -d "wordpress" ]; then
  WP_SIZE=$(du -sh wordpress 2>/dev/null | cut -f1 || echo "Unknown")
  echo "  WordPress size: $WP_SIZE"
fi
echo ""

ERROR_COUNT=$(docker compose logs --since=1h 2>/dev/null | grep -i error | wc -l || echo 0)
if [ "$ERROR_COUNT" -gt 0 ]; then
  yellow "  ⚠️  $ERROR_COUNT errors in last hour"
  echo "     Run 'make logs' to investigate"
else
  green "  ✅ No recent errors detected"
fi

echo ""
if curl -sf "${WP_URL}" >/dev/null 2>&1 &&    docker compose exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" -e "SELECT 1" "${DB_NAME}" >/dev/null 2>&1; then
  green "🎉 Environment is healthy!"
  exit 0
else
  red "❌ Environment has issues"
  exit 1
fi
HEALTH_EOF

############################################
#  Plugin development helper scripts
############################################
cat > plugin-status.sh << 'PLUGIN_STATUS_EOF'
#!/bin/bash
# Plugin development status checker
set -euo pipefail

blue() { echo -e "\033[34m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }

[ -f .env ] && source .env || { red "❌ .env file not found"; exit 1; }

blue "📦 Plugin Development Status"
echo "============================"

if [ ! -d "plugins" ]; then
  echo "No plugins directory found"
  exit 0
fi

echo "Local Plugins:"
echo "--------------"

for plugin_dir in plugins/*/; do
  if [ -d "$plugin_dir" ]; then
    plugin_name=$(basename "$plugin_dir")

    if [ -d "$plugin_dir/.git" ]; then
      echo -n "🔗 $plugin_name"

      cd "$plugin_dir"

      # Check for remote
      if git remote -v >/dev/null 2>&1; then
        remote=$(git remote get-url origin 2>/dev/null || echo "")
        if [ -n "$remote" ]; then
          echo " → $remote"
        else
          echo " (local git only)"
        fi

        # Check git status
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
          yellow "  ⚠️  Uncommitted changes"
        fi

        # Check if ahead/behind
        if git remote -v >/dev/null 2>&1 && [ -n "$remote" ]; then
          git fetch --quiet 2>/dev/null || true
          LOCAL=$(git rev-parse @ 2>/dev/null || echo "")
          REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")

          if [ -n "$LOCAL" ] && [ -n "$REMOTE" ]; then
            if [ "$LOCAL" != "$REMOTE" ]; then
              BASE=$(git merge-base @ @{u} 2>/dev/null || echo "")
              if [ "$LOCAL" = "$BASE" ]; then
                yellow "  📥 Behind remote"
              elif [ "$REMOTE" = "$BASE" ]; then
                yellow "  📤 Ahead of remote"
              else
                yellow "  🔄 Diverged from remote"
              fi
            else
              green "  ✅ Up to date"
            fi
          fi
        fi
      else
        echo " (no remote configured)"
      fi

      cd - >/dev/null
    else
      echo "📁 $plugin_name (local only, no git)"
    fi
  fi
done

echo ""
echo "WordPress Plugin Status:"
echo "----------------------"

if docker compose ps wordpress | grep -q "Up" 2>/dev/null; then
  docker compose exec -T wpcli wp plugin list --format=table 2>/dev/null || echo "WordPress not ready"
else
  echo "WordPress container not running"
fi
PLUGIN_STATUS_EOF

############################################
#  Final output + folder perms
############################################
mkdir -p plugins themes uploads backups .docker/mysql-logs wordpress
# Create .gitkeep files to maintain directory structure
touch plugins/.gitkeep themes/.gitkeep

# Dev-friendly perms so both www-data and wpcli can write
find wordpress plugins themes uploads -type d -exec chmod 0775 {} + 2>/dev/null || true
find wordpress plugins themes uploads -type f -exec chmod 0664 {} + 2>/dev/null || true
chmod 0700 backups 2>/dev/null || true

# Set proper permissions for scripts
chmod +x backup.sh restore.sh health-check.sh plugin-status.sh

# Validate generated docker-compose.yml syntax
if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
        if ! docker compose config >/dev/null 2>&1; then
            red "❌ Generated docker-compose.yml is invalid"
            exit 1
        fi
    elif command -v docker-compose >/dev/null 2>&1; then
        if ! docker-compose config >/dev/null 2>&1; then
            red "❌ Generated docker-compose.yml is invalid"
            exit 1
        fi
    fi
fi

SETUP_COMPLETE=1

echo ""
green "✅ Enhanced WordPress Development Environment created with Plugin Development Workflow!"
echo ""
blue "📁 Project location: $(pwd)"
echo ""
blue "🚀 Quick start:"
echo "   cd $PROJECT_NAME"
echo "   make up"
echo "   make install   # first time only"
echo ""
blue "🔌 Plugin Development:"
echo "   make plugin name=my-plugin          # Create new plugin"
echo "   make plugin-repo name=my-plugin     # Initialize git repo"
echo "   make plugin-clone repo=<git-url>    # Clone existing plugin"
echo "   make plugin-list                    # List all plugins"
echo "   ./plugin-status.sh                  # Detailed plugin status"
echo ""
blue "💾 Database Management:"
echo "   make backup                         # Create database backup"
echo "   make restore file=backup.sql.gz     # Restore from backup"
echo "   make db-import file=/path/to/db.sql.gz  # Import external database"
echo "   make list-backups                   # List available backups"
echo ""
blue "⚙️  Configuration (edit .env file):"
echo "   PHP_VERSION=8.4                     # PHP version (8.1, 8.2, 8.3, 8.4)"
echo "   PHP_UPLOAD_MAX_FILESIZE=128M        # Upload size limit"
echo "   PHP_MEMORY_LIMIT=512M               # PHP memory limit"
echo "   Then run: make restart"
echo ""
blue "🌐 Access URLs:"
echo "   WordPress: ${WP_URL:-http://localhost:8080}"
echo "   phpMyAdmin: http://localhost:${PMA_PORT:-8081}"
echo "   Mailpit (dev): http://localhost:${MAILPIT_HTTP_PORT:-8025}"
echo ""
yellow "⚠️  Note: plugins/ and themes/ are in .gitignore - each should have its own repository"
echo ""
