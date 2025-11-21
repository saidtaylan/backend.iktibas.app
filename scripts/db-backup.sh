#!/bin/bash
#
# Supabase Self-Hosted için Tam PostgreSQL Veritabanı Yedekleme Script'i
# pg_dumpall kullanarak tüm rolleri, şemaları ve verileri yedekler.
# Parola ve kullanıcı adını .env dosyasından okur.
#

# --- AYARLAR: BU ALANLARI KENDİNİZE GÖRE DÜZENLEYİN ---

# 1. Supabase projenizin (docker-compose.yml dosyasının olduğu) TAM YOLU
#    Cron içinde çalışacağı için $(pwd) KULLANMAYIN. Tam yolu yazın.
#    ÖRNEK: PROJECT_DIR="/opt/iktibas/backend.iktibas.app"
PROJECT_DIR="/opt/iktibas/backend.iktibas.app"

# 2. Yedeklerin saklanacağı dizin
#    Bu dizinin var olduğundan ve yazma izniniz olduğundan emin olun.
BACKUP_DIR="/opt/iktibas/db-backups"

# 3. Kaç günlük yedek saklanacak? (Örn: 7 = 7 günden eski yedekleri sil)
RETENTION_DAYS=60

# 4. Docker Compose'daki veritabanı servisinizin adı (genellikle 'db' dir)
DB_SERVICE_NAME="db"

# 5. Süper kullanıcınızın adı (NOT: Bu, .env dosyanızdaki POSTGRES_USER ile aynı olmalı)
DB_SUPERUSER="supabase_admin"

# --- SCRIPT AYARLARI BİTTİ ---

# .env dosyasının tam yolu
ENV_FILE="$PROJECT_DIR/.env"

# Hata kontrolü için
set -o pipefail

# --- .env DOSYASINI KONTROL ET VE OKU ---

if [ ! -f "$ENV_FILE" ]; then
    echo "$(date): HATA: .env dosyası bulunamadı: $ENV_FILE"
    exit 1
fi

# .env dosyasından POSTGRES_PASSWORD'u oku
# (Windows satır sonlarını (\r) temizlemek için tr -d '\r' eklendi)
DB_PASSWORD=$(grep -E '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d '=' -f2- | tr -d '\r')

if [ -z "$DB_PASSWORD" ]; then
    echo "$(date): HATA: .env dosyasında POSTGRES_PASSWORD bulunamadı."
    exit 1
fi

# --- YEDEKLEME İŞLEMİ ---

# Yedek dizininin var olduğundan emin ol
mkdir -p $BACKUP_DIR

# Dosya adı (Örn: supabase_backup_2025-11-03_2115.sql.gz)
FILENAME="supabase_backup_$(date +%Y-%m-%d_%H%M).sql.gz"
BACKUP_FILE_PATH="$BACKUP_DIR/$FILENAME"

echo "$(date): Yedekleme başlıyor: $FILENAME"

# docker compose exec komutunu PGPASSWORD ve PGUSER değişkenleriyle çalıştır
# -T bayrağı, cron içinde çalışabilmesi için terminal ayırmaz
# PGPASSWORD ve PGUSER, konteyner İÇİNDEKİ pg_dumpall komutu tarafından okunur
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T \
  -e PGPASSWORD="$DB_PASSWORD" \
  -e PGUSER="$DB_SUPERUSER" \
  $DB_SERVICE_NAME \
  pg_dumpall | gzip > $BACKUP_FILE_PATH

# Komutun başarı durumunu kontrol et
if [ $? -eq 0 ]; then
  echo "$(date): Başarılı: Yedekleme tamamlandı ve şuraya kaydedildi: $BACKUP_FILE_PATH"
else
  echo "$(date): HATA: Yedekleme sırasında bir sorun oluştu."
  rm -f $BACKUP_FILE_PATH # Başarısız olduysa boş dosyayı sil
  exit 1
fi

# --- TEMİZLİK İŞLEMİ ---

echo "$(date): Eski yedekler temizleniyor (Retention: $RETENTION_DAYS gün)..."
find $BACKUP_DIR -name "supabase_backup_*.sql.gz" -mtime +$RETENTION_DAYS -exec rm {} \;

echo "$(date): Temizlik tamamlandı."
echo "---"

exit 0
