#!/bin/bash

# Supabase Production Setup Initialization Script
# Bu script ilk kurulum için gerekli tüm dosya ve dizinleri oluşturur

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[UYARI]${NC} $1"
}

error() {
    echo -e "${RED}[HATA]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[BİLGİ]${NC} $1"
}

log "Supabase Production kurulumu için dizinler ve dosyalar oluşturuluyor..."

# Temel volume dizinlerini oluştur
info "Volume dizinleri oluşturuluyor..."

mkdir -p volumes/{nginx/{logs,conf.d},certbot/{conf,www,logs},smtp/{spool,logs},backups,redis,storage,db/data,functions}
mkdir -p volumes/{api,logs,pooler}
mkdir -p scripts

# Nginx self-signed certificate (test amaçlı)
create_self_signed_cert() {
    local domain=${1:-localhost}
    
    info "Test için self-signed SSL sertifikası oluşturuluyor: $domain"
    
    mkdir -p volumes/nginx/ssl
    
    # Self-signed certificate oluştur
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout volumes/nginx/ssl/selfsigned.key \
        -out volumes/nginx/ssl/selfsigned.crt \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=Supabase-Local/OU=IT/CN=$domain"
    
    info "Self-signed sertifika oluşturuldu: volumes/nginx/ssl/"
}

# Test nginx konfigürasyonu (SSL olmadan)
create_test_nginx_conf() {
    info "Test nginx konfigürasyonu oluşturuluyor..."
    
    cat > volumes/nginx/conf.d/supabase-test.conf << 'EOF'
# Test configuration - SSL olmadan
server {
    listen 80;
    listen [::]:80;
    server_name localhost;

    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy settings
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Supabase Studio (Dashboard)
    location /dashboard/ {
        proxy_pass http://studio:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # API routes through Kong
    location / {
        proxy_pass http://kong:8000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

    info "Test nginx konfigürasyonu oluşturuldu"
}

# Kong konfigürasyonunu kopyala (eğer yoksa)
setup_kong_config() {
    info "Kong konfigürasyonu kontrol ediliyor..."
    
    if [[ ! -f "volumes/api/kong.yml" ]]; then
        warn "Kong konfigürasyon dosyası bulunamadı"
        
        # Basit Kong konfigürasyonu oluştur
        mkdir -p volumes/api
        
        cat > volumes/api/kong.yml << 'EOF'
_format_version: "1.1"

services:
  - name: auth-v1-open
    url: http://auth:9999/verify
    routes:
      - name: auth-v1-open
        strip_path: true
        paths:
          - /auth/v1/verify

  - name: auth-v1-open-callback
    url: http://auth:9999/callback
    routes:
      - name: auth-v1-open-callback
        strip_path: true
        paths:
          - /auth/v1/callback

  - name: auth-v1-open-authorize
    url: http://auth:9999/authorize
    routes:
      - name: auth-v1-open-authorize
        strip_path: true
        paths:
          - /auth/v1/authorize

  - name: auth-v1
    _comment: "GoTrue: /auth/v1/* -> http://auth:9999/*"
    url: http://auth:9999/
    routes:
      - name: auth-v1-all
        strip_path: true
        paths:
          - /auth/v1/

  - name: rest-v1
    _comment: "PostgREST: /rest/v1/* -> http://rest:3000/*"
    url: http://rest:3000/
    routes:
      - name: rest-v1-all
        strip_path: true
        paths:
          - /rest/v1/

  - name: realtime-v1
    _comment: "Realtime: /realtime/v1/* -> ws://realtime:4000/socket/*"
    url: http://realtime:4000/socket/
    routes:
      - name: realtime-v1-all
        strip_path: true
        paths:
          - /realtime/v1/

  - name: storage-v1
    _comment: "Storage: /storage/v1/* -> http://storage:5000/*"
    url: http://storage:5000/
    routes:
      - name: storage-v1-all
        strip_path: true
        paths:
          - /storage/v1/

  - name: functions-v1
    _comment: "Edge Functions: /functions/v1/* -> http://functions:9000/*"
    url: http://functions:9000/
    routes:
      - name: functions-v1-all
        strip_path: true
        paths:
          - /functions/v1/

  - name: meta
    _comment: "PG Meta: /pg/* -> http://meta:8080/*"
    url: http://meta:8080/
    routes:
      - name: meta-all
        strip_path: true
        paths:
          - /pg/

consumers:
  - username: anon
    keyauth_credentials:
      - key: ${ANON_KEY}
  - username: service_role
    keyauth_credentials:
      - key: ${SERVICE_ROLE_KEY}

acls:
  - consumer: anon
    group: anon
  - consumer: service_role
    group: service_role

plugins:
  - name: cors
  - name: key-auth
    config:
      hide_credentials: false
  - name: acl
    config:
      hide_groups_header: true
EOF
        
        info "Basit Kong konfigürasyonu oluşturuldu"
    else
        info "Kong konfigürasyonu mevcut"
    fi
}

# Database init dosyalarını kontrol et
setup_db_init() {
    info "Database init dosyaları kontrol ediliyor..."
    
    # Temel dizinleri oluştur
    mkdir -p volumes/db
    
    # Eğer init dosyaları yoksa uyarı ver
    local init_files=("realtime.sql" "webhooks.sql" "roles.sql" "jwt.sql" "_supabase.sql" "logs.sql" "pooler.sql")
    
    for file in "${init_files[@]}"; do
        if [[ ! -f "volumes/db/$file" ]]; then
            warn "DB init dosyası eksik: $file"
            warn "Supabase resmi repo'dan bu dosyaları kopyalamanız gerekebilir"
        fi
    done
}

# Environment dosyası kontrolü
check_env_file() {
    info "Environment dosyası kontrol ediliyor..."
    
    if [[ ! -f ".env" ]]; then
        if [[ -f ".env.production" ]]; then
            info "Production environment dosyası .env olarak kopyalanıyor..."
            cp .env.production .env
        else
            warn "Environment dosyası bulunamadı!"
            warn "Lütfen .env.production dosyasını .env olarak kopyalayın ve düzenleyin"
        fi
    else
        info "Environment dosyası mevcut"
    fi
}

# Dosya izinlerini ayarla
set_permissions() {
    info "Dosya izinleri ayarlanıyor..."
    
    # Script'leri executable yap
    chmod +x *.sh 2>/dev/null || true
    chmod +x scripts/*.sh 2>/dev/null || true
    
    # Volume'lar için uygun izinler
    chmod -R 755 volumes/ 2>/dev/null || true
    
    # Backup dizini yazılabilir olmalı
    chmod 777 volumes/backups/ 2>/dev/null || true
    
    info "İzinler ayarlandı"
}

# Docker Compose dosyası kontrolü
check_compose_file() {
    info "Docker Compose dosyası kontrol ediliyor..."
    
    if [[ ! -f "docker-compose.yml" ]]; then
        error "docker-compose.yml dosyası bulunamadı!"
    fi
    
    # Dosyada production eklentilerinin olup olmadığını kontrol et
    if grep -q "nginx:" docker-compose.yml; then
        info "Production eklentileri tespit edildi ✓"
    else
        warn "docker-compose.yml dosyası orijinal halde gözüküyor"
        warn "Production eklentilerini eklemek için update-supabase.sh kullanın"
    fi
}

# Test bağlantısı
test_docker() {
    info "Docker bağlantısı test ediliyor..."
    
    if ! docker info &>/dev/null; then
        error "Docker daemon çalışmıyor veya erişilemiyor"
    fi
    
    if ! command -v docker-compose &>/dev/null && ! command -v docker compose &>/dev/null; then
        error "Docker Compose kurulu değil"
    fi
    
    info "Docker test başarılı ✓"
}

# Ana kurulum fonksiyonu
main() {
    log "Supabase Production kurulum hazırlığı başlatılıyor..."
    
    # Temel kontroller
    test_docker
    check_compose_file
    check_env_file
    
    # Dizin ve dosya kurulumu
    setup_kong_config
    setup_db_init
    create_test_nginx_conf
    set_permissions
    
    # Opsiyonel: Self-signed cert (test için)
    read -p "Test için self-signed SSL sertifikası oluşturulsun mu? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_self_signed_cert "localhost"
    fi
    
    log "Kurulum hazırlığı tamamlandı!"
    echo ""
    info "Sonraki adımlar:"
    echo "1. .env dosyasını düzenleyin (domain, şifreler vb.)"
    echo "2. ./supabase-manager.sh init  # İlk kurulum"
    echo "3. ./supabase-manager.sh start # Sistemi başlat"
    echo ""
    info "Detaylı kılavuz: README.md ve QUICKSTART.md"
}

# Script'i çalıştır
main "$@"
