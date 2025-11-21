supabase migration up --db-url "postgres://postgres:`cat pass`@172.18.0.11/postgres?sslmode=disable" --debug

Supabase CLI can be installed using deb or rpm files.
Migrations can be made connecting db: supabase migration up --db-url "postgres://postgres:`grep POSTGRES_PASSWORD .env | cut -d '=' -f1`@/postgres?sslmode=disable" --debug
