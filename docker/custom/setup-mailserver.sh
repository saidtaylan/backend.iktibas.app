#!/bin/bash

# Docker Mailserver Setup Script
# Bu script docker-mailserver'ı Supabase ile entegre eder

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

# Environment dosyasından değerleri oku
load_env() {
    if [[ -f ".env" ]]; then
        export $(grep -v '^#' .env | xargs)
    else
        error ".env dosyası bulunamadı"
    fi
}

# Mailserver dizinlerini oluştur
create_directories() {
    log "Docker Mailserver dizinleri oluşturuluyor..."
    
    mkdir -p volumes/smtp/{data,mail-state,logs,config}
    mkdir -p volumes/smtp/config/{postfix,dovecot}
    
    # İzinleri ayarla
    chmod -R 755 volumes/smtp/
    
    info "Dizinler oluşturuldu"
}

# Mailserver konfigürasyon dosyalarını oluştur
create_config() {
    log "Mailserver konfigürasyonu oluşturuluyor..."
    
    # Docker Mailserver postfix main.cf override
    cat > volumes/smtp/config/postfix-main.cf << 'EOF'
# Supabase SMTP Configuration
# Relay için optimize edilmiş ayarlar

# Network ve host ayarları
myhostname = $OVERRIDE_HOSTNAME
mydomain = $OVERRIDE_HOSTNAME
myorigin = $mydomain
inet_interfaces = all
inet_protocols = ipv4

# Relay ayarları (Supabase için)
relayhost = 
smtp_use_tls = yes
smtp_tls_security_level = may

# SASL Authentication
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = $myhostname

# Restrictions
smtpd_helo_required = yes
smtpd_client_restrictions = permit_mynetworks,reject
smtpd_sender_restrictions = permit_mynetworks,reject
smtpd_recipient_restrictions = permit_mynetworks,reject

# Message size limits
message_size_limit = 51200000
mailbox_size_limit = 0

# Queue settings
maximal_queue_lifetime = 1d
bounce_queue_lifetime = 1d
EOF

    # Docker Mailserver dovecot override (minimal)
    cat > volumes/smtp/config/dovecot.cf << 'EOF'
# Minimal Dovecot config for SMTP-only mode
# Bu dosya SMTP_ONLY=1 modunda kullanılmaz ama placeholder olarak gerekli
auth_mechanisms = plain login
EOF

    info "Konfigürasyon dosyaları oluşturuldu"
}

# Supabase Auth için SMTP ayarlarını güncelle
update_supabase_smtp() {
    log "Supabase SMTP ayarları güncelleniyor..."
    
    # .env dosyasında SMTP ayarlarını kontrol et
    local smtp_host=${SMTP_HOST:-smtp}
    local smtp_port=${SMTP_PORT:-587}
    local smtp_user=${SMTP_USER:-noreply}
    local admin_email=${SMTP_ADMIN_EMAIL:-admin@localhost}
    
    info "SMTP Host: $smtp_host"
    info "SMTP Port: $smtp_port" 
    info "SMTP User: $smtp_user"
    info "Admin Email: $admin_email"
    
    # Supabase Auth servisinin SMTP ayarlarını kontrol et
    if grep -q "GOTRUE_SMTP_HOST.*smtp" docker-compose.yml; then
        info "✓ Supabase Auth SMTP konfigürasyonu mevcut"
    else
        warn "Supabase Auth SMTP konfigürasyonu eksik olabilir"
    fi
}

# Mail kullanıcısı oluştur
setup_mail_user() {
    local email=${1:-noreply@${SMTP_DOMAIN:-localhost}}
    local password=${2:-${SMTP_PASS:-changeme}}
    
    log "Mail kullanıcısı oluşturuluyor: $email"
    
    # setup.sh script'ini kullanarak kullanıcı ekle
    cat > volumes/smtp/setup-user.sh << EOF
#!/bin/bash
# Bu script container başladıktan sonra çalıştırılacak
docker exec supabase-smtp setup email add $email $password
docker exec supabase-smtp setup alias add postmaster@${SMTP_DOMAIN:-localhost} $email
EOF

    chmod +x volumes/smtp/setup-user.sh
    
    info "Kullanıcı setup script'i hazırlandı: volumes/smtp/setup-user.sh"
    warn "Container başladıktan sonra şu komutu çalıştırın:"
    warn "./volumes/smtp/setup-user.sh"
}

# Test email konfigürasyonu
create_test_config() {
    log "Test email konfigürasyonu oluşturuluyor..."
    
    cat > volumes/smtp/test-email.sh << EOF
#!/bin/bash
# Test email gönderme script'i

SMTP_HOST=${SMTP_HOST:-smtp}
SMTP_PORT=${SMTP_PORT:-587}
FROM_EMAIL=${SMTP_USER:-noreply}@${SMTP_DOMAIN:-localhost}
TO_EMAIL=\${1:-test@example.com}
SUBJECT="Supabase SMTP Test"
BODY="Bu bir test email'idir. Supabase SMTP konfigürasyonu çalışıyor!"

echo "Test email gönderiliyor..."
echo "From: \$FROM_EMAIL"
echo "To: \$TO_EMAIL"
echo "Subject: \$SUBJECT"
echo ""

# Test email gönder
docker exec supabase-smtp /bin/bash -c "
echo '\$BODY' | mail -s '\$SUBJECT' -a 'From: \$FROM_EMAIL' \$TO_EMAIL
"

echo "Test email gönderildi!"
EOF

    chmod +x volumes/smtp/test-email.sh
    
    info "Test script oluşturuldu: volumes/smtp/test-email.sh"
}

# Ana setup fonksiyonu
main() {
    log "Docker Mailserver setup başlatılıyor..."
    
    # Environment yükle
    load_env
    
    # Dizinler ve konfigürasyon
    create_directories
    create_config
    
    # Supabase entegrasyonu
    update_supabase_smtp
    
    # Mail kullanıcısı setup'ı
    setup_mail_user "${SMTP_USER:-noreply}@${SMTP_DOMAIN:-localhost}" "${SMTP_PASS:-changeme}"
    
    # Test konfigürasyonu
    create_test_config
    
    log "Docker Mailserver setup tamamlandı!"
    echo ""
    info "Sonraki adımlar:"
    echo "1. docker-compose up -d smtp  # SMTP servisini başlat"
    echo "2. ./volumes/smtp/setup-user.sh  # Mail kullanıcısını oluştur"
    echo "3. ./volumes/smtp/test-email.sh your-email@domain.com  # Test email gönder"
    echo ""
    info "SMTP ayarları:"
    echo "Host: ${SMTP_HOST:-smtp}"
    echo "Port: ${SMTP_PORT:-587} (STARTTLS)"
    echo "User: ${SMTP_USER:-noreply}@${SMTP_DOMAIN:-localhost}"
    echo "Pass: ${SMTP_PASS:-changeme}"
}

# Script'i çalıştır
main "$@"
