-- NASCinema database bootstrap. Run ONCE as a PostgreSQL superuser:
--
--   psql -U postgres -f scripts/init_db.sql
--
-- Idempotent. Change the password for anything beyond local dev, and set a
-- matching NASCINEMA_DATABASE_URL in your .env. Nothing here is hardcoded into
-- the app — these are just the role/db the connection string points at.

DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'nascinema') THEN
      CREATE ROLE nascinema LOGIN PASSWORD 'nascinema';
   END IF;
END
$$;

SELECT 'CREATE DATABASE nascinema OWNER nascinema'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'nascinema')
\gexec
