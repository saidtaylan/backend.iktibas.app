# 🚀 Supabase Production - Hızlı Kurulum

Bu rehber ile Supabase'i production ortamında 15 dakikada kurabilirsiniz.

## ⚡ Hızlı Adımlar

### 1. Sistem Hazırlığı (2 dk)

```bash
# Docker ve Docker Compose kurulu olduğunu kontrol edin
docker --version
docker-compose --version

# Supabase repo'yu klonlayın
git clone https://github.com/supabase/supabase.git
cd supabase/docker
```

### 2. Environment Ayarları (5 dk)

```bash
# Production env dosyasını kopyalayın
cp .env.production .env

# Kritik ayarları düzenleyin
nano .env
```

**Mutlaka değiştirmeniz gerekenler:**

```bash
DOMAIN_NAME=yourdomain.com                    # Kendi domain'iniz
SUPABASE_PUBLIC_URL=https://yourdomain.com
POSTGRES_PASSWORD=super-güçlü-şifre-123!      # Güçlü DB şifresi
JWT_SECRET=32-karakter-uzun-güçlü-jwt-secret  # JWT secret
ANON_KEY=anon-key-32-karakter-uzunluğunda     # Anon key
SERVICE_ROLE_KEY=service-role-key-güçlü       # Service role key
DASHBOARD_PASSWORD=admin-şifre-güçlü          # Dashboard şifresi
SMTP_ADMIN_EMAIL=admin@yourdomain.com         # Admin email
```

### 3. İlk Kurulum (5 dk)

```bash
# Kurulum script'ini çalıştırın
chmod +x *.sh
./supabase-manager.sh init
```

Bu script:
- Gerekli dizinleri oluşturur
- SSL sertifikası alır (Let's Encrypt)
- Tüm servisleri başlatır

### 4. Sistem Başlatma (2 dk)

```bash
# Sistemi başlatın
./supabase-manager.sh start

# Durum kontrolü
./supabase-manager.sh status
```

### 5. Erişim Testi (1 dk)

Tarayıcınızda kontrol edin:

- **Dashboard**: `https://yourdomain.com/dashboard/`
  - Username: `supabase`
  - Password: `.env`'deki `DASHBOARD_PASSWORD`

- **API**: `https://yourdomain.com/rest/v1/`

## 🔧 İlk Konfigürasyon

### Database Studio Erişimi

1. `https://yourdomain.com/dashboard/` adresine gidin
2. Sol menüden "SQL Editor" seçin
3. İlk tablolarınızı oluşturun

### Auth Ayarları

1. Dashboard'da "Authentication" bölümüne gidin
2. "Settings" > "General" 
3. Site URL'ini kontrol edin: `https://yourdomain.com`
4. Email templates'i özelleştirin

### API Keys

Dashboard'da "Settings" > "API" bölümünden:
- `anon` key: Frontend'de kullanın
- `service_role` key: Backend'de kullanın (GÜVENLİ tutun!)

## 🚦 Hızlı Komutlar

```bash
# Sistem durumu
./supabase-manager.sh status

# Log'ları izle
./supabase-manager.sh logs

# Backup al
./supabase-manager.sh backup

# SSL yenile
./supabase-manager.sh ssl-renew

# Servisleri scale et
./scale-services.sh production
```

## 🆘 Sorun mu var?

### SSL Sertifikası Alınamıyor

```bash
# Domain DNS ayarlarını kontrol edin
nslookup yourdomain.com

# Manuel SSL kurulumu
./supabase-manager.sh ssl-setup
```

### Servislere Erişilemiyor

```bash
# Container durumları
docker ps | grep supabase

# Nginx log'ları
./supabase-manager.sh logs nginx

# Kong log'ları
./supabase-manager.sh logs kong
```

### Database Bağlantı Hatası

```bash
# DB container durumu
./supabase-manager.sh logs db

# Şifre kontrolü
grep POSTGRES_PASSWORD .env
```

## 🎯 Sonraki Adımlar

1. **Güvenlik**: Şifreleri güçlü yapın
2. **Backup**: Otomatik backup'ların çalıştığını kontrol edin
3. **Monitoring**: `./supabase-manager.sh health` ile düzenli kontrol
4. **Scaling**: Trafiğe göre `./scale-services.sh` kullanın
5. **Updates**: Haftalık `./update-supabase.sh check` yapın

## 📱 Client Bağlantısı

### JavaScript/TypeScript

```bash
npm install @supabase/supabase-js
```

```js
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://yourdomain.com'
const supabaseKey = 'your-anon-key'  // .env'deki ANON_KEY

export const supabase = createClient(supabaseUrl, supabaseKey)
```

### Python

```bash
pip install supabase
```

```python
from supabase import create_client, Client

url = "https://yourdomain.com"
key = "your-anon-key"  # .env'deki ANON_KEY

supabase: Client = create_client(url, key)
```

## 🔄 Güncellemeler

```bash
# Haftalık güncelleme kontrolü
./update-supabase.sh check

# Güncelleme uygulama
./update-supabase.sh update
```

Güncellemeler production eklentilerinizi etkilemez!

---

**Tebrikler! 🎉** Supabase production kurulumunuz hazır. Detaylar için `README.md` dosyasına bakın.
