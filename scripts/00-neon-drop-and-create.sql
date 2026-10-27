-- Run connected to neondb (admin). Names must stay quoted (mixed case).
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname IN ('dbAether1Year', 'dbAether2Year')
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS "dbAether1Year" WITH (FORCE);
DROP DATABASE IF EXISTS "dbAether2Year" WITH (FORCE);

CREATE DATABASE "dbAether2Year";
CREATE DATABASE "dbAether1Year";
