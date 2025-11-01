# iktibas Multi-Provider Integration System

Kullanıcıların readspace alıntılarını/kitaplarını farklı external platformlara (Notion, Google Docs, OneDrive vb.) senkronize edebileceği sistem.

## 🏗️ Sistem Mimarisi

### Core Bileşenler

1. **Database Schema** - PostgreSQL tabloları ve constraints
2. **Edge Functions** - Supabase serverless functions
3. **Type Definitions** - TypeScript interface'leri
4. **Provider Adapters** - Her platform için özel implementasyonlar

### Desteklenen Platformlar

- ✅ **Notion** - API key ile authentication, sayfa bazlı sync
- 🚧 **Google Docs** - OAuth2 ile authentication, dokuman bazlı sync  
- 🚧 **OneDrive** - OAuth2 ile authentication, dosya bazlı sync

## 📋 Kurulum

### 1. Migration'ı Çalıştır

```bash
cd supabase
supabase db reset
# veya sadece yeni migration
supabase db push
```

### 2. Environment Variables

`.env.local` dosyası oluşturun:

```bash
# .env.integration.example dosyasını kopyalayın
cp .env.integration.example .env.local

# Değerleri doldurun
INTEGRATION_ENCRYPTION_KEY="your-32-character-encryption-key-here"
NOTION_TEST_API_KEY="secret_your-notion-api-key"
```

### 3. Edge Functions Deploy

```bash
# Integration auth function
supabase functions deploy integration-auth

# Integration sync function  
supabase functions deploy integration-sync
```

### 4. Schema Validation

```bash
# Migration'ların başarılı olduğunu doğrula
supabase db exec --file scripts/validate_integration_schema.sql

# Test verilerini çalıştır
supabase db exec --file scripts/test_integration_system.sql
```

## 🔧 API Kullanımı

### 1. Available Provider'ları Listele

```typescript
const { data: providers } = await supabase
  .from('providers')
  .select('*')
  .eq('is_active', true);
```

### 2. Yeni Integration Oluştur

```typescript
// Edge function çağırarak
const response = await supabase.functions.invoke('integration-sync', {
  body: {
    action: 'create_integration',
    provider_name: 'notion',
    readspace_id: 'uuid',
    integration_name: 'My Notion Workspace',
    credentials: {
      api_key: 'secret_xxx',
      workspace_url: 'https://myworkspace.notion.so'
    },
    sync_settings: {
      auto_sync: false,
      sync_frequency: 'manual',
      sync_direction: 'to_provider_only',
      target_config: {
        main_page_id: 'abc123',
        books_page_id: 'def456',
        quotes_page_id: 'ghi789'
      }
    }
  }
});
```

### 3. Connection Validate Et

```typescript
const response = await supabase.functions.invoke('integration-sync', {
  body: {
    action: 'validate_connection',
    integration_id: 'integration-uuid'
  }
});
```

### 4. Content Sync Yap

```typescript
const response = await supabase.functions.invoke('integration-sync', {
  body: {
    action: 'sync_content',
    integration_id: 'integration-uuid',
    sync_type: 'manual'
  }
});
```

### 5. Available Destinations Al

```typescript
const response = await supabase.functions.invoke('integration-sync', {
  body: {
    action: 'get_destinations',
    integration_id: 'integration-uuid'
  }
});
```

## 🔐 Güvenlik

### Credential Encryption

Tüm provider credentials AES-256-GCM ile şifrelenir:

```typescript
// Şifreleme için
const response = await supabase.functions.invoke('integration-auth', {
  body: {
    action: 'encrypt',
    payload: {
      provider_name: 'notion',
      credentials: { api_key: 'secret_xxx' }
    }
  }
});
```

### Row Level Security (RLS)

- Her kullanıcı sadece kendi integration'larını görebilir
- Provider tablosu herkes tarafından okunabilir
- Sync logs sadece integration sahibi tarafından görülebilir

### Rate Limiting

Provider API limitlerini aşmamak için:
- Notion: 100 request/minute
- Google Docs: 60 request/minute  
- OneDrive: 50 request/minute

## 📊 Database Schema

### Ana Tablolar

```sql
-- Provider tanımları
providers (id, name, display_name, auth_type, api_base_url, ...)

-- Kullanıcı integration'ları  
readspace_integrations (id, user_id, provider_id, readspace_id, credentials, ...)

-- Hedef destinasyonlar
integration_destinations (id, readspace_integration_id, type, external_id, ...)

-- Sync işlem logları
sync_logs (id, readspace_integration_id, sync_type, status, ...)
```

### Mevcut Tablolara Eklenenler

```sql
-- Books tablosuna
ALTER TABLE books ADD COLUMN sync_data JSONB DEFAULT '{}';

-- Quotes tablosuna  
ALTER TABLE quotes ADD COLUMN sync_data JSONB DEFAULT '{}';
```

### Sync Data Yapısı

```json
{
  "notion": {
    "page_id": "abc123",
    "url": "https://notion.so/abc123", 
    "last_synced_at": "2024-01-01T00:00:00Z",
    "sync_status": "synced",
    "content_hash": "sha256_hash"
  },
  "google_docs": {
    "document_id": "doc123",
    "url": "https://docs.google.com/document/d/doc123"
  }
}
```

## 🧪 Testing

### Manuel Test

```bash
# Schema validation
supabase db exec --file scripts/validate_integration_schema.sql

# Integration system test  
supabase db exec --file scripts/test_integration_system.sql
```

### Unit Tests (Web/Mobile)

```typescript
import { describe, it, expect } from 'vitest';
import { isValidNotionUrl, extractNotionPageId } from './integration';

describe('Integration Utils', () => {
  it('validates Notion URLs correctly', () => {
    expect(isValidNotionUrl('https://myworkspace.notion.so/Page-abc123')).toBe(true);
    expect(isValidNotionUrl('https://invalid.com')).toBe(false);
  });

  it('extracts Notion page IDs', () => {
    const url = 'https://myworkspace.notion.so/Page-abc123def456';
    expect(extractNotionPageId(url)).toBe('abc123def456');
  });
});
```

## 🚀 Deployment

### Production Environment

```bash
# Production'da şu environment variables gerekli:
INTEGRATION_ENCRYPTION_KEY="production-32-char-key"
NOTION_RATE_LIMIT_PER_MINUTE=100
GOOGLE_RATE_LIMIT_PER_MINUTE=60
```

### Monitoring

```sql
-- Sync success rate
SELECT 
  p.display_name,
  COUNT(*) as total_syncs,
  COUNT(*) FILTER (WHERE sl.status = 'synced') as successful_syncs,
  ROUND(
    COUNT(*) FILTER (WHERE sl.status = 'synced') * 100.0 / COUNT(*), 2
  ) as success_rate_percent
FROM sync_logs sl
JOIN readspace_integrations ri ON sl.readspace_integration_id = ri.id  
JOIN providers p ON ri.provider_id = p.id
WHERE sl.started_at >= NOW() - INTERVAL '7 days'
GROUP BY p.display_name;
```

### Alerting

- Failed sync rate > 10%
- Connection validation failures
- Credential expiration warnings
- API rate limit approaching

## 📱 Frontend Integration

### Web (Nuxt)

```typescript
// stores/integration.ts
export const useIntegrationStore = defineStore('integration', () => {
  const integrations = ref<ReadspaceIntegration[]>([]);
  
  const createIntegration = async (data: CreateIntegrationRequest) => {
    // API call implementation
  };
  
  const syncContent = async (integrationId: string) => {
    // Sync implementation
  };
  
  return { integrations, createIntegration, syncContent };
});
```

### Mobile (Flutter)

```dart
class IntegrationService {
  Future<List<Provider>> getProviders() async {
    // API call implementation
  }
  
  Future<ReadspaceIntegration> createIntegration(CreateIntegrationRequest request) async {
    // Create integration implementation  
  }
  
  Future<SyncResults> syncContent(String integrationId) async {
    // Sync implementation
  }
}
```

## 🔍 Troubleshooting

### Common Issues

1. **Migration fails**: `readspaces` tablosu yoksa önce core schema'yı çalıştırın
2. **RLS errors**: Test kullanıcısının `auth.users`'da olduğunu kontrol edin
3. **Credential encryption fails**: `INTEGRATION_ENCRYPTION_KEY` 32 karakter olmalı
4. **Notion API errors**: API key format'ının doğru olduğunu kontrol edin

### Debug Queries

```sql
-- Active integrations
SELECT ri.*, p.display_name 
FROM readspace_integrations ri 
JOIN providers p ON ri.provider_id = p.id 
WHERE ri.status = 'active';

-- Recent sync logs
SELECT * FROM sync_logs 
ORDER BY started_at DESC 
LIMIT 10;

-- Books/quotes with sync data
SELECT title, sync_data 
FROM books 
WHERE sync_data != '{}'::jsonb;
```

## 🔮 Future Roadmap

### Phase 3: Advanced Features
- [ ] Bidirectional sync
- [ ] Conflict resolution
- [ ] Incremental sync optimization
- [ ] Webhook notifications

### Phase 4: Additional Providers  
- [ ] Obsidian
- [ ] Roam Research
- [ ] Logseq
- [ ] Evernote

### Phase 5: Enterprise Features
- [ ] Team sync settings
- [ ] Audit logs  
- [ ] Advanced permissions
- [ ] Custom provider SDK

## 📞 Support

Integration sisteminde sorun yaşarsanız:

1. Önce troubleshooting section'ını kontrol edin
2. Validation script'ini çalıştırın
3. Debug query'leri kullanın
4. GitHub issue açın

---

**Not**: Bu sistem production-ready değildir. Test ortamında kullanın ve güvenlik incelemesi yaptırın.
