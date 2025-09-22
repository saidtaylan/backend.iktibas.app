#!/bin/bash

# Supabase Production Management Script
# Bu script Supabase kurulumunuzu yönetmek için kullanılır

set -e

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Değişkenler
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
BACKUP_DIR="./volumes/backups"

# Log fonksiyonu
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

# Yardım fonksiyonu
show_help() {
    echo "Supabase Production Manager"
    echo ""
    echo "Kullanım: $0 [KOMUT] [OPSIYONLAR]"
    echo ""
    echo "Komutlar:"
    echo "  init              - İlk kurulum ve SSL sertifikası alma"
    echo "  start             - Tüm servisleri başlat"
    echo "  stop              - Tüm servisleri durdur"
    echo "  restart           - Tüm servisleri yeniden başlat"
    echo "  status            - Servis durumlarını göster"
    echo "  logs [SERVIS]     - Log'ları göster (servis belirtilmezse tümü)"
    echo "  backup            - Manuel backup al"
    echo "  restore FILE      - Backup'tan geri yükle"
    echo "  scale SERVIS=NUM  - Servisi scale et (örn: scale db=2)"
    echo "  update            - Servisleri güncelle"
    echo "  ssl-renew         - SSL sertifikasını yenile"
    echo "  ssl-setup         - İlk SSL kurulumu"
    echo "  cleanup           - Eski volume'ları ve container'ları temizle"
    echo "  health            - Sistem sağlık kontrolü"
    echo ""
    echo "Örnekler:"
    echo "  $0 init                    # İlk kurulum"
    echo "  $0 start                   # Sistemi başlat"
    echo "  $0 logs nginx              # Nginx log'larını göster"
    echo "  $0 scale functions=3       # Edge functions'ı 3'e çıkar"
    echo "  $0 backup                  # Manuel backup al"
}

# Ön kontroller
check_prerequisites() {
    if [[ ! -f "$ENV_FILE" ]]; then
        error "Environment dosyası bulunamadı: $ENV_FILE"
    fi
    
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Docker Compose dosyası bulunamadı: $COMPOSE_FILE"
    fi
    
    if ! command -v docker &> /dev/null; then
        error "Docker kurulu değil"
    fi
    
    if ! command -v docker-compose &> /dev/null && ! command -v docker compose &> /dev/null; then
        error "Docker Compose kurulu değil"
    fi
}

# Docker Compose komutu tespiti
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# SSL kurulumu
ssl_setup() {
    log "SSL sertifikası kurulumu başlatılıyor..."
    
    # Domain kontrolü
    if ! grep -q "DOMAIN_NAME=" "$ENV_FILE"; then
        error "DOMAIN_NAME environment dosyasında tanımlanmamış"
    fi
    
    DOMAIN_NAME=$(grep "DOMAIN_NAME=" "$ENV_FILE" | cut -d'=' -f2)
    
    if [[ -z "$DOMAIN_NAME" || "$DOMAIN_NAME" == "your-domain.com" ]]; then
        error "Geçerli bir domain adı tanımlanmamış. .env dosyasını düzenleyin."
    fi
    
    info "Domain: $DOMAIN_NAME"
    
    # Nginx ve Certbot'u çalıştır
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD up -d nginx certbot
    
    # İlk sertifika alma
    log "Let's Encrypt sertifikası alınıyor..."
    $COMPOSE_CMD exec certbot certbot certonly \
        --webroot \
        --webroot-path=/var/www/certbot \
        --email admin@$DOMAIN_NAME \
        --agree-tos \
        --no-eff-email \
        -d $DOMAIN_NAME
    
    # Nginx'i yeniden başlat
    $COMPOSE_CMD restart nginx
    
    log "SSL kurulumu tamamlandı"
}

# İlk kurulum
init() {
    log "Supabase Production kurulumu başlatılıyor..."
    
    check_prerequisites
    
    # Gerekli dizinleri oluştur
    log "Gerekli dizinler oluşturuluyor..."
    mkdir -p volumes/{nginx/logs,certbot/{conf,www,logs},smtp/{spool,logs},backups,redis,storage,db/data,functions}
    mkdir -p volumes/api volumes/logs volumes/pooler
    
    # İlk SSL kurulumu (eğer domain tanımlıysa)
    if grep -q "DOMAIN_NAME=your-domain.com" "$ENV_FILE"; then
        warn "Domain adı varsayılan değerde. SSL kurulumu atlanıyor."
        warn "Domain'inizi .env dosyasında tanımladıktan sonra 'ssl-setup' komutunu çalıştırın."
    else
        ssl_setup
    fi
    
    log "Kurulum tamamlandı. Sistemi başlatmak için: $0 start"
}

# Sistem başlatma
start() {
    log "Supabase servisleri başlatılıyor..."
    check_prerequisites
    
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD up -d
    
    log "Servisler başlatıldı. Durum kontrolü için: $0 status"
}

# Sistem durdurma
stop() {
    log "Supabase servisleri durduruluyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD down
    
    log "Servisler durduruldu"
}

# Sistem yeniden başlatma
restart() {
    log "Supabase servisleri yeniden başlatılıyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD restart
    
    log "Servisler yeniden başlatıldı"
}

# Durum kontrolü
status() {
    log "Servis durumları kontrol ediliyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD ps
}

# Log görüntüleme
show_logs() {
    local service=$1
    COMPOSE_CMD=$(get_compose_cmd)
    
    if [[ -n "$service" ]]; then
        info "$service servis log'ları:"
        $COMPOSE_CMD logs -f --tail=100 "$service"
    else
        info "Tüm servis log'ları:"
        $COMPOSE_CMD logs -f --tail=50
    fi
}

# Manuel backup
backup() {
    log "Manuel backup başlatılıyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD exec db-backup /usr/local/bin/backup.sh
    
    log "Backup tamamlandı. Dosyalar: $BACKUP_DIR"
    ls -lah "$BACKUP_DIR"/supabase_backup_*.sql.gz 2>/dev/null | tail -5
}

# Backup'tan geri yükleme
restore() {
    local backup_file=$1
    
    if [[ -z "$backup_file" ]]; then
        error "Backup dosyası belirtilmedi. Kullanım: $0 restore DOSYA_ADI"
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup dosyası bulunamadı: $backup_file"
    fi
    
    warn "Bu işlem mevcut veritabanını siler ve backup'tan geri yükler!"
    read -p "Devam etmek istiyor musunuz? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Backup'tan geri yükleme başlatılıyor..."
        
        COMPOSE_CMD=$(get_compose_cmd)
        
        # DB'yi durdur
        $COMPOSE_CMD stop db
        
        # Backup'ı geri yükle
        if [[ "$backup_file" == *.gz ]]; then
            gunzip -c "$backup_file" | $COMPOSE_CMD exec -T db psql -U postgres
        else
            $COMPOSE_CMD exec -T db psql -U postgres < "$backup_file"
        fi
        
        # DB'yi başlat
        $COMPOSE_CMD start db
        
        log "Geri yükleme tamamlandı"
    else
        log "İşlem iptal edildi"
    fi
}

# Servis scale etme
scale_service() {
    local scale_param=$1
    
    if [[ -z "$scale_param" || ! "$scale_param" =~ ^[a-zA-Z-]+=[0-9]+$ ]]; then
        error "Geçersiz scale parametresi. Kullanım: $0 scale SERVIS=SAYI"
    fi
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    log "Servis scale ediliyor: $scale_param"
    $COMPOSE_CMD up -d --scale "$scale_param"
    
    log "Scale işlemi tamamlandı"
}

# Güncelleme
update() {
    log "Supabase servisleri güncelleniyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    # Image'ları güncelle
    $COMPOSE_CMD pull
    
    # Servisleri yeniden başlat
    $COMPOSE_CMD up -d --force-recreate
    
    log "Güncelleme tamamlandı"
}

# SSL yenileme
ssl_renew() {
    log "SSL sertifikası yenileniyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    $COMPOSE_CMD exec certbot certbot renew
    $COMPOSE_CMD restart nginx
    
    log "SSL yenileme tamamlandı"
}

# Temizlik
cleanup() {
    log "Sistem temizliği başlatılıyor..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    # Durmuş container'ları temizle
    $COMPOSE_CMD down --remove-orphans
    
    # Kullanılmayan volume'ları temizle
    docker volume prune -f
    
    # Kullanılmayan image'ları temizle
    docker image prune -f
    
    log "Temizlik tamamlandı"
}

# Sağlık kontrolü
health_check() {
    log "Sistem sağlık kontrolü..."
    
    COMPOSE_CMD=$(get_compose_cmd)
    
    echo ""
    info "Container durumları:"
    $COMPOSE_CMD ps
    
    echo ""
    info "Disk kullanımı:"
    df -h | grep -E "(Filesystem|/dev/)"
    
    echo ""
    info "Son backup'lar:"
    ls -lah "$BACKUP_DIR"/supabase_backup_*.sql.gz 2>/dev/null | tail -3 || echo "Backup bulunamadı"
    
    echo ""
    info "SSL sertifika durumu:"
    if [[ -d "./volumes/certbot/conf/live" ]]; then
        find ./volumes/certbot/conf/live -name "cert.pem" -exec openssl x509 -in {} -text -noout \; 2>/dev/null | grep -A 2 "Validity" || echo "SSL bilgisi alınamadı"
    else
        echo "SSL sertifikası kurulu değil"
    fi
}

# Ana komut işleyici
case "${1:-help}" in
    init)
        init
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        show_logs "$2"
        ;;
    backup)
        backup
        ;;
    restore)
        restore "$2"
        ;;
    scale)
        scale_service "$2"
        ;;
    update)
        update
        ;;
    ssl-setup)
        ssl_setup
        ;;
    ssl-renew)
        ssl_renew
        ;;
    cleanup)
        cleanup
        ;;
    health)
        health_check
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Bilinmeyen komut: $1. Yardım için: $0 help"
        ;;
esac
