#!/bin/bash

# Supabase Services Scaling Script
# Bu script servislerinizi kolayca scale etmenizi sağlar

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

show_help() {
    echo "Supabase Services Scaling Script"
    echo ""
    echo "Kullanım: $0 [PROFIL] veya $0 custom SERVIS=SAYI [SERVIS2=SAYI2]..."
    echo ""
    echo "Hazır Profiller:"
    echo "  light       - Hafif kullanım (1 instance her servis)"
    echo "  medium      - Orta kullanım (DB: 2, Functions: 2, diğerleri: 1)"
    echo "  heavy       - Yoğun kullanım (DB: 3, Functions: 4, Auth: 2, diğerleri: 2)"
    echo "  production  - Production önerilen (DB: 2, Functions: 3, Auth: 2, Storage: 2)"
    echo "  custom      - Özel scaling (sonrasında servis=sayı belirtin)"
    echo ""
    echo "Scale edilebilir servisler:"
    echo "  - functions (Edge Functions)"
    echo "  - auth (Authentication)"
    echo "  - rest (PostgREST API)"
    echo "  - storage (Storage API)"
    echo "  - realtime (Realtime)"
    echo "  - meta (Postgres Meta)"
    echo ""
    echo "Örnekler:"
    echo "  $0 medium                          # Orta kullanım profilini uygula"
    echo "  $0 custom functions=5 auth=3       # Edge Functions'ı 5, Auth'u 3'e çıkar"
    echo "  $0 status                          # Mevcut scale durumunu göster"
    echo ""
    echo "Not: Database (db) servisi tek instance olarak çalışır (clustering dışında)."
}

# Docker Compose komutu tespiti
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# Mevcut durumu göster
show_status() {
    log "Mevcut servis durumları:"
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    echo ""
    info "Container sayıları:"
    $COMPOSE_CMD ps --format "table {{.Service}}\t{{.State}}\t{{.Ports}}" | grep -E "(SERVICE|supabase-)"
    
    echo ""
    info "Detaylı durum:"
    $COMPOSE_CMD ps
}

# Light profil - Minimum kaynak kullanımı
apply_light() {
    log "Light profil uygulanıyor (minimum kaynak)..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    $COMPOSE_CMD up -d --scale functions=1 \
                      --scale auth=1 \
                      --scale rest=1 \
                      --scale storage=1 \
                      --scale realtime=1 \
                      --scale meta=1
    
    log "Light profil uygulandı"
}

# Medium profil - Orta düzey kullanım
apply_medium() {
    log "Medium profil uygulanıyor (orta düzey)..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    $COMPOSE_CMD up -d --scale functions=2 \
                      --scale auth=1 \
                      --scale rest=1 \
                      --scale storage=2 \
                      --scale realtime=1 \
                      --scale meta=1
    
    log "Medium profil uygulandı"
}

# Heavy profil - Yoğun kullanım
apply_heavy() {
    log "Heavy profil uygulanıyor (yoğun kullanım)..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    $COMPOSE_CMD up -d --scale functions=4 \
                      --scale auth=2 \
                      --scale rest=2 \
                      --scale storage=2 \
                      --scale realtime=2 \
                      --scale meta=2
    
    log "Heavy profil uygulandı"
}

# Production profil - Production önerilen
apply_production() {
    log "Production profil uygulanıyor (önerilen production)..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    $COMPOSE_CMD up -d --scale functions=3 \
                      --scale auth=2 \
                      --scale rest=2 \
                      --scale storage=2 \
                      --scale realtime=2 \
                      --scale meta=1
    
    log "Production profil uygulandı"
}

# Custom scaling
apply_custom() {
    local scale_params=("$@")
    
    if [[ ${#scale_params[@]} -eq 0 ]]; then
        error "Custom scaling için en az bir servis=sayı parametresi gerekli"
    fi
    
    log "Custom scaling uygulanıyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    # Scale parametrelerini validate et
    for param in "${scale_params[@]}"; do
        if [[ ! "$param" =~ ^[a-zA-Z-]+=[0-9]+$ ]]; then
            error "Geçersiz format: $param. Doğru format: servis=sayı"
        fi
        
        service=$(echo "$param" | cut -d'=' -f1)
        count=$(echo "$param" | cut -d'=' -f2)
        
        # Geçerli servis kontrolü
        case "$service" in
            functions|auth|rest|storage|realtime|meta)
                info "✓ $service servisi $count instance'a scale edilecek"
                ;;
            db|postgres)
                warn "Database servisi scale edilemez (clustering olmadan)"
                continue
                ;;
            *)
                warn "Bilinmeyen servis: $service (atlanıyor)"
                continue
                ;;
        esac
    done
    
    # Scale uygula
    scale_args=""
    for param in "${scale_params[@]}"; do
        service=$(echo "$param" | cut -d'=' -f1)
        case "$service" in
            functions|auth|rest|storage|realtime|meta)
                scale_args="$scale_args --scale $param"
                ;;
        esac
    done
    
    if [[ -n "$scale_args" ]]; then
        $COMPOSE_CMD up -d $scale_args
        log "Custom scaling uygulandı"
    else
        warn "Hiçbir geçerli scale parametresi bulunamadı"
    fi
}

# Resource monitoring
monitor_resources() {
    log "Kaynak kullanımı izleniyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    echo ""
    info "CPU ve Memory kullanımı:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -20
    
    echo ""
    info "Disk kullanımı:"
    df -h | grep -E "(Filesystem|/dev/)"
    
    echo ""
    info "Container durumları:"
    $COMPOSE_CMD ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"
}

# Otomatik scaling önerisi
suggest_scaling() {
    log "Otomatik scaling önerisi hesaplanıyor..."
    
    # CPU kullanımını kontrol et
    high_cpu_containers=$(docker stats --no-stream --format "{{.Container}} {{.CPUPerc}}" | awk '$2 > 80 {print $1}' | wc -l)
    
    if [[ $high_cpu_containers -gt 0 ]]; then
        warn "$high_cpu_containers container yüksek CPU kullanıyor (>80%)"
        info "Öneri: heavy veya production profili deneyin"
    fi
    
    # Memory kullanımını kontrol et  
    high_mem_containers=$(docker stats --no-stream --format "{{.Container}} {{.MemPerc}}" | awk '$2 > 80 {print $1}' | wc -l)
    
    if [[ $high_mem_containers -gt 0 ]]; then
        warn "$high_mem_containers container yüksek memory kullanıyor (>80%)"
        info "Öneri: Sistem kaynaklarını artırın veya scaling yapın"
    fi
    
    # Toplam container sayısı
    total_containers=$(docker ps --format "{{.Names}}" | grep supabase | wc -l)
    info "Toplam aktif Supabase container: $total_containers"
}

# Ana komut işleyici
case "${1:-help}" in
    light)
        apply_light
        ;;
    medium)
        apply_medium
        ;;
    heavy)
        apply_heavy
        ;;
    production)
        apply_production
        ;;
    custom)
        shift
        apply_custom "$@"
        ;;
    status)
        show_status
        ;;
    monitor)
        monitor_resources
        ;;
    suggest)
        suggest_scaling
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Bilinmeyen komut: $1. Yardım için: $0 help"
        ;;
esac
