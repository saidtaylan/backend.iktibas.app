# Supabase Migrations

- Bu klasör, Supabase CLI tarafından sıralı olarak çalıştırılan SQL migration dosyalarını içerir.
- Dosyalar lexicographic sıraya göre uygulanır. Bu nedenle dosya adlarının başında timestamp kullanılır.

## Dosya Adlandırma

```
<timestamp>__v<SemVer>__<kısa_açıklama>.sql
```

Örnek:
```
20250826124848__v1.0.0__create_app_versions.sql
```

- `<timestamp>` biçimi: `YYYYMMDDHHMMSS` (UTC zorunlu değil; tekil ve sıralı olması yeterli)
- `v<SemVer>`: Uygulama sürümü ile bağ kurmak için dokümantatif amaçlıdır (CLI için zorunlu değil)
- `<kısa_açıklama>`: Migration’ı özetleyen kısa bir ifade

## Up/Down Blokları

Supabase CLI yerleşik “down/rollback” komutu sağlamaz. Production geri dönüşleri yeni bir ileri migration ile yapılmalıdır. Yine de dosyalarımıza aşağıdaki yorum işaretleri ile down SQL’ini referans amaçlı ekliyoruz:

```sql
-- app_semver: v1.0.0
-- migrate:up
-- (buraya çalışacak up SQL’leri gelir)

-- migrate:down
-- (buraya aynı migration’ı geri alacak down SQL KOMUTLARI yorum olarak yazılır)
```

CLI yalnızca yorum olmayan SQL satırlarını uygular. `-- migrate:down` bloğu yorumda kalır; production geri dönüş gerekiyorsa bu bloktan yararlanılarak yeni bir “ileri” migration hazırlanır.

## CLI Akışları

- Yerelde ileri migrate: `supabase migration up`
- Yerelde belirli bir sürüme reset: `supabase db reset --version <timestamp>`
- Uzak (remote) dağıtım: `supabase db push`

Notlar:
- Preview branch rollback: branch’i silip PR’ı yeniden açmak, seed ve migration’ların baştan çalışması için önerilen yoldur.
- Production rollback: “down” değişikliklerini içeren yeni bir ileri migration dosyası oluşturup `supabase db push` ile dağıtın.
