To dump supabase db spesific schemas
```
supabase db dump -s public,auth,storage,cron -f supabase/migrations/05092025-baseline_schema.sql --db-url postgres://
```