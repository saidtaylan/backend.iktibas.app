#!/bin/bash

# Supabase Update and Sync Script
# Bu script Supabase'i orijinal repo ile senkronize eder ve günceller

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

# Konfigürasyon
SUPABASE_REPO_URL="https://github.com/supabase/supabase.git"
TEMP_DIR="/tmp/supabase-update-$(date +%s)"
COMPOSE_FILE="docker-compose.yml"
BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"

show_help() {
    echo "Supabase Update and Sync Script"
    echo ""
    echo "Bu script Supabase'in orijinal docker-compose dosyasını indirir,"
    echo "sizin production değişikliklerinizle merge eder ve güncelleri uygular."
    echo ""
    echo "Kullanım: $0 [KOMUT]"
    echo ""
    echo "Komutlar:"
    echo "  check       - Yeni güncellemeleri kontrol et (download etmeden)"
    echo "  update      - Güncellemeleri indir ve uygula"
    echo "  sync        - Orijinal repo ile senkronize et"
    echo "  backup      - Mevcut konfigürasyonu yedekle"
    echo "  restore     - Yedekten geri yükle"
    echo "  diff        - Mevcut ve orijinal arasındaki farkları göster"
    echo ""
    echo "Güvenlik:"
    echo "  Script çalışmadan önce otomatik backup alır"
    echo "  Production eklentileriniz korunur"
    echo "  Sadece Supabase servis versiyonları güncellenir"
    echo ""
    echo "Örnekler:"
    echo "  $0 check     # Güncellemeleri kontrol et"
    echo "  $0 update    # Güncellemeleri uygula"
    echo "  $0 diff      # Farklılıkları göster"
}

# Backup alma
create_backup() {
    log "Mevcut konfigürasyon yedekleniyor..."
    
    mkdir -p "$BACKUP_DIR"
    cp -r . "$BACKUP_DIR/" 2>/dev/null || true
    
    # Gereksiz dosyaları backup'tan çıkar
    rm -rf "$BACKUP_DIR/volumes/db/data" 2>/dev/null || true
    rm -rf "$BACKUP_DIR/volumes/storage" 2>/dev/null || true
    rm -rf "$BACKUP_DIR/volumes/backups" 2>/dev/null || true
    
    log "Backup oluşturuldu: $BACKUP_DIR"
}

# Orijinal repo'yu klonla
clone_original() {
    log "Supabase orijinal reposu indiriliyor..."
    
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    git clone --depth 1 "$SUPABASE_REPO_URL" "$TEMP_DIR"
    
    if [[ ! -f "$TEMP_DIR/docker/docker-compose.yml" ]]; then
        error "Orijinal docker-compose.yml dosyası bulunamadı"
    fi
    
    log "Orijinal repo indirildi: $TEMP_DIR"
}

# Versiyonları karşılaştır
compare_versions() {
    log "Servis versiyonları karşılaştırılıyor..."
    
    if [[ ! -f "$TEMP_DIR/docker/docker-compose.yml" ]]; then
        error "Orijinal dosya bulunamadı. Önce 'clone_original' çalıştırın"
    fi
    
    echo ""
    info "Mevcut vs Yeni Versiyonlar:"
    echo "=================================="
    
    # Image'ları çıkar ve karşılaştır
    extract_images() {
        local file=$1
        grep -E "image:" "$file" | sed 's/.*image: //' | sed 's/[ \t]*$//' | sort
    }
    
    mevcut_images=$(extract_images "$COMPOSE_FILE")
    yeni_images=$(extract_images "$TEMP_DIR/docker/docker-compose.yml")
    
    # Farkları göster
    while IFS= read -r image; do
        service_name=$(echo "$image" | cut -d':' -f1 | cut -d'/' -f2)
        mevcut_version=$(echo "$mevcut_images" | grep "$service_name" | head -1)
        yeni_version=$(echo "$yeni_images" | grep "$service_name" | head -1)
        
        if [[ "$mevcut_version" != "$yeni_version" ]]; then
            echo -e "${YELLOW}$service_name:${NC}"
            echo "  Mevcut: $mevcut_version"
            echo "  Yeni:   $yeni_version"
            echo ""
        fi
    done <<< "$yeni_images"
}

# Sadece versiyonları kontrol et
check_updates() {
    log "Güncellemeler kontrol ediliyor..."
    
    clone_original
    compare_versions
    
    # Temizlik
    rm -rf "$TEMP_DIR"
    
    log "Kontrol tamamlandı"
}

# Farklılıkları göster
show_diff() {
    log "Dosya farklılıkları analiz ediliyor..."
    
    clone_original
    
    echo ""
    info "Docker Compose dosyası farklılıkları:"
    echo "====================================="
    
    # Sadece orijinal Supabase servislerini karşılaştır
    # Production eklentilerini (nginx, certbot, smtp vb.) filtrele
    
    # Geçici dosya oluştur (production eklentileri olmadan)
    temp_current="/tmp/current-clean.yml"
    temp_original="/tmp/original-clean.yml"
    
    # Production eklentilerini çıkar
    sed '/# Nginx reverse proxy/,/studio:/d' "$COMPOSE_FILE" | \
    sed '/^  nginx:/,/^  [a-z]/{ /^  [a-z]/!d; }' | \
    sed '/^  certbot:/,/^  [a-z]/{ /^  [a-z]/!d; }' | \
    sed '/^  smtp:/,/^  [a-z]/{ /^  [a-z]/!d; }' | \
    sed '/^  db-backup:/,/^  [a-z]/{ /^  [a-z]/!d; }' | \
    sed '/^  redis:/,/^  [a-z]/{ /^  [a-z]/!d; }' > "$temp_current"
    
    cp "$TEMP_DIR/docker/docker-compose.yml" "$temp_original"
    
    # Diff göster
    if command -v colordiff &> /dev/null; then
        colordiff -u "$temp_original" "$temp_current" || true
    else
        diff -u "$temp_original" "$temp_current" || true
    fi
    
    # Temizlik
    rm -f "$temp_current" "$temp_original"
    rm -rf "$TEMP_DIR"
}

# Production değişikliklerini tespit et
extract_production_changes() {
    log "Production değişiklikleri çıkarılıyor..."
    
    # Production servislerini ayır
    production_services="/tmp/production-services.yml"
    
    # Nginx, Certbot, SMTP, backup, redis servislerini çıkar
    sed -n '/# Nginx reverse proxy/,/studio:/p' "$COMPOSE_FILE" | \
    sed '/studio:/d' > "$production_services"
    
    # SMTP konfigürasyonundaki değişiklikleri de çıkar
    smtp_configs=$(grep -A 10 -B 10 "GOTRUE_SMTP_HOST.*smtp" "$COMPOSE_FILE" | \
                   grep "GOTRUE_SMTP" | \
                   grep -v "GOTRUE_SMTP_HOST: \${SMTP_HOST}$" | \
                   grep -v "GOTRUE_SMTP_PORT: \${SMTP_PORT}$" | \
                   grep -v "GOTRUE_SMTP_USER: \${SMTP_USER}$" | \
                   grep -v "GOTRUE_SMTP_PASS: \${SMTP_PASS}$" || true)
    
    echo "$production_services"
}

# Güncellemeleri uygula
apply_update() {
    log "Güncelleme uygulanıyor..."
    
    # Backup al
    create_backup
    
    # Orijinal repo'yu indir
    clone_original
    
    # Production değişikliklerini çıkar
    extract_production_changes
    
    log "Yeni docker-compose.yml oluşturuluyor..."
    
    # Yeni compose dosyası oluştur
    temp_new_compose="/tmp/new-compose.yml"
    
    # Başlık ve services başlığını kopyala
    head -10 "$TEMP_DIR/docker/docker-compose.yml" > "$temp_new_compose"
    
    # Production servislerini ekle
    if [[ -f "/tmp/production-services.yml" ]]; then
        cat "/tmp/production-services.yml" >> "$temp_new_compose"
    fi
    
    # Orijinal Supabase servislerini ekle (studio'dan başlayarak)
    sed -n '/^  studio:/,$p' "$TEMP_DIR/docker/docker-compose.yml" >> "$temp_new_compose"
    
    # Kong ve Analytics portlarını düzelt (production için expose'a çevir)
    sed -i 's/    ports:/    expose:/' "$temp_new_compose"
    sed -i 's/      - ${KONG_HTTP_PORT}:8000\/tcp/      - "8000"/' "$temp_new_compose"
    sed -i 's/      - ${KONG_HTTPS_PORT}:8443\/tcp/      - "8443"/' "$temp_new_compose"
    sed -i 's/      - 4000:4000/      - "4000"/' "$temp_new_compose"
    
    # SMTP konfigürasyonunu güncelle
    sed -i 's/GOTRUE_SMTP_HOST: ${SMTP_HOST}/GOTRUE_SMTP_HOST: ${SMTP_HOST:-smtp}/' "$temp_new_compose"
    sed -i 's/GOTRUE_SMTP_PORT: ${SMTP_PORT}/GOTRUE_SMTP_PORT: ${SMTP_PORT:-25}/' "$temp_new_compose"
    sed -i 's/GOTRUE_SMTP_USER: ${SMTP_USER}/GOTRUE_SMTP_USER: ${SMTP_USER:-admin}/' "$temp_new_compose"
    sed -i 's/GOTRUE_SMTP_PASS: ${SMTP_PASS}/GOTRUE_SMTP_PASS: ${SMTP_PASS:-changeme}/' "$temp_new_compose"
    
    # Eski dosyayı yedekle ve yenisiyle değiştir
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak"
    cp "$temp_new_compose" "$COMPOSE_FILE"
    
    log "docker-compose.yml güncellendi"
    
    # Servisleri yeniden başlat (eğer çalışıyorsa)
    if docker-compose ps | grep -q "Up"; then
        warn "Servisler çalışıyor. Yeniden başlatmak istiyor musunuz? (y/N)"
        read -p "> " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Servisler yeniden başlatılıyor..."
            docker-compose down
            docker-compose pull
            docker-compose up -d
            log "Servisler güncellenerek başlatıldı"
        else
            info "Servisler yeniden başlatılmadı. Manuel başlatmak için:"
            info "  docker-compose down && docker-compose pull && docker-compose up -d"
        fi
    fi
    
    # Temizlik
    rm -rf "$TEMP_DIR" "/tmp/production-services.yml" "$temp_new_compose" 2>/dev/null || true
    
    log "Güncelleme tamamlandı!"
    info "Backup konumu: $BACKUP_DIR"
}

# Yedekten geri yükle
restore_backup() {
    local backup_path=$1
    
    if [[ -z "$backup_path" ]]; then
        # En son backup'ı bul
        backup_path=$(ls -1d backup-* 2>/dev/null | sort -r | head -1)
        
        if [[ -z "$backup_path" ]]; then
            error "Backup bulunamadı"
        fi
        
        warn "En son backup kullanılacak: $backup_path"
    fi
    
    if [[ ! -d "$backup_path" ]]; then
        error "Backup dizini bulunamadı: $backup_path"
    fi
    
    warn "Bu işlem mevcut konfigürasyonu siler!"
    read -p "Devam etmek istiyor musunuz? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Backup'tan geri yükleniyor: $backup_path"
        
        # Kritik dosyaları geri yükle
        cp "$backup_path/docker-compose.yml" . 2>/dev/null || true
        cp "$backup_path/.env" . 2>/dev/null || true
        cp -r "$backup_path/volumes" . 2>/dev/null || true
        
        log "Geri yükleme tamamlandı"
    else
        log "İşlem iptal edildi"
    fi
}

# Ana komut işleyici
case "${1:-help}" in
    check)
        check_updates
        ;;
    update)
        apply_update
        ;;
    sync)
        apply_update
        ;;
    backup)
        create_backup
        ;;
    restore)
        restore_backup "$2"
        ;;
    diff)
        show_diff
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Bilinmeyen komut: $1. Yardım için: $0 help"
        ;;
esac
