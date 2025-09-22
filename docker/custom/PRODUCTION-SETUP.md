# 🏗️ Supabase Production Setup - Teknik Detaylar

Bu döküman, production setup'ının teknik detaylarını ve mimarisini açıklar.

## 🏛️ Mimari Genel Bakış

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└─────────────────────┬───────────────────────────────────────┘
                      │
              ┌───────▼────────┐
              │   Nginx (SSL)   │ ← Let's Encrypt Certbot
              │   Port 80/443   │
              └───────┬────────┘
                      │
              ┌───────▼────────┐
              │   Kong Gateway  │ ← API Gateway & Auth
              │   Port 8000     │
              └───────┬────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
    ┌───▼───┐    ┌───▼───┐    ┌───▼─────┐
    │Studio │    │ Auth  │    │PostgREST│
    │:3000  │    │:9999  │    │  :3000  │
    └───────┘    └───────┘    └─────────┘
        │             │             │
        └─────────────┼─────────────┘
                      │
        ┌─────────────▼─────────────┐
        │      PostgreSQL + Redis   │
        │        Database           │
        └─────────────┬─────────────┘
                      │
        ┌─────────────▼─────────────┐
        │     Backup Service        │
        │    (6 saatte bir)         │
        └───────────────────────────┘
```

## 📁 Dizin Yapısı

```
supabase/docker/
├── docker-compose.yml          # Ana compose dosyası (production enhanced)
├── .env.production             # Production environment template
├── .env                        # Aktif environment (sizin ayarlarınız)
│
├── scripts/
│   └── backup.sh              # DB backup script
│
├── volumes/
│   ├── nginx/
│   │   ├── nginx.conf         # Ana nginx konfigürasyonu
│   │   ├── conf.d/
│   │   │   └── supabase.conf  # Supabase-specific nginx config
│   │   └── logs/              # Nginx log'ları
│   │
│   ├── certbot/
│   │   ├── conf/              # SSL sertifikaları
│   │   ├── www/               # ACME challenge
│   │   └── logs/              # Certbot log'ları
│   │
│   ├── smtp/
│   │   ├── spool/             # Mail queue
│   │   └── logs/              # SMTP log'ları
│   │
│   ├── backups/               # Database backup'ları
│   ├── redis/                 # Redis persistence
│   ├── storage/               # Supabase storage files
│   └── db/                    # PostgreSQL data
│
├── supabase-manager.sh        # Ana yönetim script'i
├── scale-services.sh          # Scaling yönetimi
├── update-supabase.sh         # Güncelleme yönetimi
├── init-setup.sh              # İlk kurulum hazırlığı
│
├── README.md                  # Ana dokümantasyon
├── QUICKSTART.md             # Hızlı kurulum
└── PRODUCTION-SETUP.md       # Bu dosya
```

## 🔧 Production Değişiklikleri

### Orijinal Supabase'e Eklenenler

1. **Nginx Reverse Proxy**
   - SSL/TLS termination
   - Rate limiting
   - Security headers
   - Load balancing hazır

2. **Certbot (Let's Encrypt)**
   - Otomatik SSL sertifikası
   - Otomatik yenileme (12 saatte bir)
   - Multi-domain support

3. **SMTP Server**
   - Postfix tabanlı internal SMTP
   - Supabase Auth ile entegre
   - Mail queue yönetimi

4. **Database Backup Service**
   - Her 6 saatte otomatik backup
   - Compressed backup'lar (.gz)
   - Retention policy (7 gün)
   - Sistem ve ana DB backup

5. **Redis Cache**
   - Session cache
   - Query cache potansiyeli
   - Persistence aktif

6. **Enhanced Monitoring**
   - Structured logging
   - Health check endpoints
   - Performance metrics

### Değiştirilmeyen Orijinal Servisler

Aşağıdaki servisler **hiç değiştirilmedi**:
- **studio**: Supabase Dashboard
- **auth**: GoTrue Authentication
- **rest**: PostgREST API
- **realtime**: Realtime subscriptions  
- **storage**: File storage
- **imgproxy**: Image processing
- **meta**: PostgreSQL metadata
- **functions**: Edge Functions
- **analytics**: Logflare analytics
- **db**: PostgreSQL database
- **vector**: Log processing
- **supavisor**: Connection pooler

## 🔐 Güvenlik Implementasyonu

### SSL/TLS Konfigürasyonu

```nginx
# Modern SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;

# HSTS (HTTP Strict Transport Security)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### Rate Limiting

```nginx
# API ve Auth için farklı rate limit'ler
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;
```

### Security Headers

- `X-Frame-Options: DENY`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`

## 🚀 Scaling Stratejisi

### Horizontal Scaling

Aşağıdaki servisler scale edilebilir:

```yaml
# Light (minimum kaynak)
functions: 1 instance
auth: 1 instance
rest: 1 instance
storage: 1 instance
realtime: 1 instance

# Production (önerilen)
functions: 3 instances
auth: 2 instances  
rest: 2 instances
storage: 2 instances
realtime: 2 instances

# Heavy (yoğun kullanım)
functions: 4 instances
auth: 2 instances
rest: 2 instances
storage: 2 instances
realtime: 2 instances
```

### Vertical Scaling

Docker Compose ile resource limit'leri:

```yaml
services:
  db:
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2'
        reservations:
          memory: 2G
          cpus: '1'
```

## 🔄 Güncelleme Mekanizması

### Güvenli Güncelleme Süreci

1. **Backup Alma**: Her güncelleme öncesi otomatik backup
2. **Diff Analizi**: Değişiklikleri karşılaştırma
3. **Selective Update**: Sadece Supabase servis versiyonları güncellenir
4. **Production Preservation**: Nginx, Certbot, SMTP ayarları korunur
5. **Rollback**: Hata durumunda geri alma

### Güncelleme Komutu

```bash
# Güvenli güncelleme
./update-supabase.sh update
```

Bu komut:
- Orijinal Supabase repo'dan son versiyonu çeker
- Production eklentilerinizi korur
- Sadece gerekli versiyonları günceller
- Otomatik backup alır

## 📊 Monitoring ve Alerting

### Log Yönetimi

```bash
# Nginx access logs
tail -f volumes/nginx/logs/access.log

# SSL certificate logs  
tail -f volumes/certbot/logs/letsencrypt.log

# SMTP logs
tail -f volumes/smtp/logs/mail.log

# Database backup logs
docker logs supabase-db-backup
```

### Performance Monitoring

```bash
# Resource usage
./scale-services.sh monitor

# Container stats
docker stats --no-stream | grep supabase

# Disk usage
df -h volumes/
```

### Health Checks

Tüm servisler için health check'ler aktif:

```yaml
healthcheck:
  test: ["CMD", "curl", "http://localhost:3000/health"]
  interval: 10s
  timeout: 5s
  retries: 3
```

## 🔧 Özelleştirme Noktaları

### 1. Nginx Konfigürasyonu

`volumes/nginx/conf.d/supabase.conf` dosyasını düzenleyerek:
- Custom domain'ler ekleyebilirsiniz
- Rate limit'leri ayarlayabilirsiniz  
- Ek security header'ları ekleyebilirsiniz

### 2. SMTP Ayarları

External SMTP kullanmak için `.env` dosyasında:

```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
```

### 3. Backup Stratejisi

`scripts/backup.sh` dosyasını düzenleyerek:
- Backup sıklığını değiştirebilirsiniz
- S3'e upload ekleyebilirsiniz
- Şifreleme ekleyebilirsiniz

### 4. Scaling Profilleri

`scale-services.sh` dosyasına yeni profiller ekleyebilirsiniz:

```bash
apply_custom_profile() {
    $COMPOSE_CMD up -d --scale functions=10 \
                      --scale auth=3 \
                      --scale rest=3
}
```

## 🚨 Felaket Kurtarma

### Tam Sistem Crash'i

```bash
# 1. Servisleri durdur
./supabase-manager.sh stop

# 2. En son backup'ı bul
ls -la volumes/backups/ | tail -5

# 3. Backup'tan geri yükle
./supabase-manager.sh restore volumes/backups/latest-backup.sql.gz

# 4. Sistemi yeniden başlat
./supabase-manager.sh start
```

### SSL Sertifikası Problemi

```bash
# Manuel SSL yenileme
./supabase-manager.sh ssl-renew

# SSL kurulumunu sıfırla
rm -rf volumes/certbot/conf/live/
./supabase-manager.sh ssl-setup
```

### Database Corruption

```bash
# PostgreSQL recovery mode
docker-compose exec db pg_resetwal -f /var/lib/postgresql/data

# Son tutarlı backup'tan restore
./supabase-manager.sh restore [backup-file]
```

## 📈 Performans Optimizasyonu

### PostgreSQL Tuning

Database container'ında:

```sql
-- Connection pooling
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '4MB';

-- Logging
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_min_duration_statement = 1000;
```

### Redis Optimizasyonu

```bash
# Redis memory policy
redis-cli CONFIG SET maxmemory-policy allkeys-lru
redis-cli CONFIG SET maxmemory 256mb
```

### Nginx Optimizasyonu

```nginx
# Worker processes
worker_processes auto;
worker_connections 1024;

# Caching
proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=my_cache:10m max_size=10g 
                 inactive=60m use_temp_path=off;
```

## 🔮 Gelecek Planları

Bu setup sürekli geliştirilmekte:

1. **Kubernetes Support**: K8s deployment seçeneği
2. **Multi-Region**: Çoklu bölge desteği
3. **Advanced Monitoring**: Prometheus/Grafana entegrasyonu
4. **Auto-Scaling**: CPU/Memory tabanlı otomatik scaling
5. **CI/CD Integration**: GitLab/GitHub Actions entegrasyonu

## 📞 Destek

Teknik problemler için:
- GitHub Issues açın
- Supabase Discord'una katılın  
- Dokümantasyonu kontrol edin

Bu production setup'ı, enterprise-grade Supabase deployment'ı için tasarlanmıştır ve sürekli güncellenmektedir.
