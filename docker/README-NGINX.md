# Nginx Reverse Proxy - HTTP (Port 80)

Supabase için basit HTTP reverse proxy konfigürasyonu.

## Özellikler

- ✅ HTTP üzerinden çalışır (Port 80)
- ✅ Kong Gateway'e proxy
- ✅ Studio Dashboard desteği
- ✅ WebSocket desteği (Realtime için)
- ✅ Güvenlik başlıkları
- ✅ Gzip compression
- ✅ Health check endpoint

## Kullanım

### Servisleri Başlatın

```bash
cd /Users/saidtaylan/Developer/iktibas/backend.iktibas/docker
docker-compose up -d
```

### Erişim

- **API**: http://localhost/
- **Studio**: http://localhost/project/
- **Health Check**: http://localhost/health

### Nginx Yeniden Yükle

Konfigürasyon değişikliği yaptıktan sonra:

```bash
docker-compose exec nginx nginx -s reload
```

### Logları Görüntüle

```bash
# Nginx container logları
docker-compose logs nginx

# Nginx access log
tail -f volumes/nginx/logs/access.log

# Nginx error log
tail -f volumes/nginx/logs/error.log
```

## Konfigürasyon Dosyaları

- **Ana config**: `volumes/nginx/nginx.conf`
- **Site config**: `volumes/nginx/conf.d/supabase.conf`
- **Loglar**: `volumes/nginx/logs/`

## Environment Değişkenleri

`.env` dosyasında:

```env
DOMAIN_NAME=localhost
SUPABASE_PUBLIC_URL=http://localhost
```

## Endpoint'ler

| Endpoint | Hedef | Açıklama |
|----------|-------|----------|
| `/` | `kong:8000` | Ana Supabase API |
| `/project/` | `studio:3000` | Dashboard |
| `/realtime/` | `kong:8000/realtime/` | WebSocket (Realtime) |
| `/health` | Nginx | Health check |

## Sorun Giderme

### Nginx başlamıyor

```bash
# Konfigürasyon testi
docker-compose exec nginx nginx -t

# Logları kontrol et
docker-compose logs nginx
```

### Kong'a bağlanamıyor

```bash
# Kong'un çalıştığını kontrol et
docker-compose ps kong

# Kong logları
docker-compose logs kong
```

### Port 80 kullanımda

```bash
# Port 80'i kullanan servisi bul
sudo lsof -i :80

# Veya
sudo netstat -tulpn | grep :80
```

## Production İçin Notlar

Production ortamında SSL/TLS kullanmanız önerilir. SSL kurulumu için ayrı bir konfigürasyon gerekir.
