# Supabase Production Docker Setup

Bu, Supabase'i production ortamında self-hosting yapmak için kapsamlı bir Docker Compose kurulumudur. 
Orijinal Supabase docker-compose.yml dosyasına ek olarak production için gerekli tüm bileşenler eklenmiştir.

## 🚀 Özellikler

### Production-Ready Bileşenler
- **Nginx Reverse Proxy** - SSL/TLS termination ve load balancing
- **Let's Encrypt SSL** - Otomatik SSL sertifikası yönetimi (Certbot)
- **SMTP Server** - Internal mail server kurulumu
- **Otomatik Backup** - 6 saatte bir database backup
- **Redis Cache** - Performans optimizasyonu
- **Monitoring** - Geliştirilmiş logging ve health checks
- **Security** - Production güvenlik önlemleri

### Yönetim Araçları
- **Supabase Manager** (`supabase-manager.sh`) - Sistem yönetimi
- **Service Scaling** (`scale-services.sh`) - Otomatik/manuel scaling
- **Update Manager** (`update-supabase.sh`) - Güncelleme yönetimi

### Güvenlik Özellikleri
- TLS 1.2/1.3 SSL encryption
- Rate limiting
- Security headers (HSTS, X-Frame-Options, etc.)
- Internal network isolation
- Strong password policies

## 📋 Sistem Gereksinimleri

- **OS**: Linux (Ubuntu 20.04+, CentOS 8+) veya macOS
- **Docker**: 20.10+
- **Docker Compose**: v2.0+
- **RAM**: Minimum 4GB, Önerilen 8GB+
- **Disk**: Minimum 20GB boş alan
- **Network**: Public IP ve domain adı (SSL için)

## 🛠 Kurulum

### 1. Temel Kurulum

```bash
# Repository'yi klonlayın
git clone https://github.com/supabase/supabase.git
cd supabase/docker

# Production environment dosyasını kopyalayın
cp .env.production .env

# Environment dosyasını düzenleyin
nano .env
```

### 2. Environment Konfigürasyonu

`.env` dosyasında **mutlaka değiştirmeniz gereken** ayarlar:

```bash
# Domain ve URL'ler
DOMAIN_NAME=your-domain.com
SUPABASE_PUBLIC_URL=https://your-domain.com
API_EXTERNAL_URL=https://your-domain.com
SITE_URL=https://your-domain.com

# Güvenlik (GÜÇ LÜ ŞİFRELER KULLANIN!)
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-change-this
SERVICE_ROLE_KEY=your-service-role-key-change-this
ANON_KEY=your-anon-key-change-this
POSTGRES_PASSWORD=your-super-secret-db-password-change-this
DASHBOARD_PASSWORD=your-dashboard-password-change-this

# SMTP Konfigürasyonu
SMTP_ADMIN_EMAIL=admin@your-domain.com
SMTP_DOMAIN=your-domain.com
```

### 3. İlk Kurulum ve Başlatma

```bash
# Kurulum script'ini çalıştırın
./supabase-manager.sh init

# Sistemi başlatın
./supabase-manager.sh start
```

## 📖 Kullanım Kılavuzu

### Temel Komutlar

```bash
# Sistem durumu
./supabase-manager.sh status

# Servisleri başlat/durdur
./supabase-manager.sh start
./supabase-manager.sh stop
./supabase-manager.sh restart

# Log'ları görüntüle
./supabase-manager.sh logs               # Tüm log'lar
./supabase-manager.sh logs nginx         # Sadece nginx log'ları

# Manuel backup al
./supabase-manager.sh backup

# Sistem sağlık kontrolü
./supabase-manager.sh health
```

### Scaling İşlemleri

```bash
# Hazır profiller
./scale-services.sh light       # Minimum kaynak
./scale-services.sh medium      # Orta düzey
./scale-services.sh production  # Production önerilen
./scale-services.sh heavy       # Yoğun kullanım

# Özel scaling
./scale-services.sh custom functions=5 auth=3

# Kaynak monitoring
./scale-services.sh monitor
./scale-services.sh suggest     # Otomatik öneri
```

### Güncelleme Yönetimi

```bash
# Güncellemeleri kontrol et
./update-supabase.sh check

# Güncellemeleri uygula
./update-supabase.sh update

# Farklılıkları görüntüle
./update-supabase.sh diff
```

## 🔧 Konfigürasyon Detayları

### SSL/TLS Kurulumu

SSL sertifikaları Let's Encrypt ile otomatik olarak alınır:

```bash
# Manuel SSL kurulumu (gerekirse)
./supabase-manager.sh ssl-setup

# SSL yenileme
./supabase-manager.sh ssl-renew
```

### Database Backup

- Otomatik backup: Her 6 saatte bir
- Backup konumu: `./volumes/backups/`
- Retention: 7 gün (değiştirilebilir)

```bash
# Manuel backup
./supabase-manager.sh backup

# Backup'tan geri yükleme
./supabase-manager.sh restore backup-file.sql.gz
```

### SMTP Konfigürasyonu

Internal SMTP server otomatik kurulur:

- **Host**: `smtp` (container içi)
- **Port**: `25`
- **Authentication**: `admin` / `changeme` (değiştirin!)

## 🚦 Servis Erişim URL'leri

SSL kurulumu tamamlandığında:

- **Supabase Studio**: `https://your-domain.com/dashboard/`
- **API Endpoint**: `https://your-domain.com/rest/v1/`
- **Auth**: `https://your-domain.com/auth/v1/`
- **Storage**: `https://your-domain.com/storage/v1/`
- **Realtime**: `wss://your-domain.com/realtime/v1/`
- **Edge Functions**: `https://your-domain.com/functions/v1/`

## 📊 Monitoring ve Logs

### Log Konumları

```
volumes/
├── nginx/logs/          # Nginx access/error logs
├── certbot/logs/        # SSL sertifika logs
├── smtp/logs/           # SMTP server logs
└── backups/             # Database backup'ları
```

### Health Check

```bash
# Sistem sağlık kontrolü
./supabase-manager.sh health

# Container durumları
docker ps | grep supabase

# Kaynak kullanımı
docker stats --no-stream
```

## 🔒 Güvenlik Önerileri

### 1. Güvenlik Ayarları

- Güçlü şifreler kullanın (minimum 32 karakter)
- JWT secret'ları düzenli olarak değiştirin
- Database şifrelerini güçlü yapın
- Dashboard erişimini kısıtlayın

### 2. Network Güvenliği

- Firewall kullanın (sadece 80, 443 portları açık)
- VPN erişimi düşünün
- DDoS koruması ekleyin
- Rate limiting aktif

### 3. Backup Güvenliği

- Backup'ları şifreleyin
- Off-site backup yapın
- Düzenli restore testleri yapın

## 🚨 Sorun Giderme

### Yaygın Sorunlar

**1. SSL Sertifikası Alınamıyor**
```bash
# Domain DNS'ini kontrol edin
nslookup your-domain.com

# Port 80'in açık olduğundan emin olun
./supabase-manager.sh ssl-setup
```

**2. Database Bağlantı Hatası**
```bash
# Container durumunu kontrol edin
./supabase-manager.sh status

# Database log'larını kontrol edin
./supabase-manager.sh logs db
```

**3. Nginx 502 Error**
```bash
# Upstream servisleri kontrol edin
./supabase-manager.sh logs kong
./supabase-manager.sh logs studio
```

**4. Yüksek Memory Kullanımı**
```bash
# Scaling yapın
./scale-services.sh medium

# Kaynak kullanımını izleyin
./scale-services.sh monitor
```

### Kritik Hatalar

**Sistem Çökmesi**
```bash
# Tüm servisleri durdur
./supabase-manager.sh stop

# Backup'tan geri yükle
./supabase-manager.sh restore

# Sistemi yeniden başlat
./supabase-manager.sh start
```

## 📈 Performans Optimizasyonu

### 1. Database Optimizasyonu

```sql
-- Bağlantı havuzu ayarları
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
```

### 2. Scaling Stratejisi

| Kullanım | Functions | Auth | Storage | DB Pool |
|----------|-----------|------|---------|---------|
| Light    | 1         | 1    | 1       | 15      |
| Medium   | 2         | 1    | 2       | 25      |
| Heavy    | 4         | 2    | 2       | 35      |
| Production| 3        | 2    | 2       | 30      |

### 3. Cache Stratejisi

- Redis cache aktif
- CDN kullanımı önerilir
- Static asset optimization

## 🔄 Güncelleme Stratejisi

### Otomatik Güncelleme

Haftalık güncelleme kontrolü için cron job ekleyin:

```bash
# Crontab'a ekleyin
0 2 * * 0 /path/to/update-supabase.sh check
```

### Manuel Güncelleme

```bash
# 1. Backup al
./supabase-manager.sh backup

# 2. Güncellemeleri kontrol et
./update-supabase.sh check

# 3. Güncellemeleri uygula
./update-supabase.sh update
```

## 📞 Destek ve Katkı

### Yardım Alın

- **Supabase Docs**: https://supabase.com/docs
- **GitHub Issues**: https://github.com/supabase/supabase/issues
- **Discord Community**: https://discord.supabase.com

### Bu Setup'ı Geliştirin

Production eklentileri orijinal Supabase servislerini etkilemez. 
Güncellemeler güvenle uygulanabilir.

## 📄 Lisans

Bu production setup MIT lisansı altında sunulmaktadır.
Orijinal Supabase projesi Apache 2.0 lisansına tabidir.
