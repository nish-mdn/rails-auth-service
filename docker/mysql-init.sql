-- MySQL initialization script for Docker

-- Create auth service database (redundant but safe)
CREATE DATABASE IF NOT EXISTS auth_service_development;
CREATE DATABASE IF NOT EXISTS auth_service_test;
CREATE DATABASE IF NOT EXISTS auth_service_production;

-- Create application user (will be done via env vars in docker-compose)
-- GRANT ALL PRIVILEGES ON auth_service_*.* TO 'auth_user'@'%' IDENTIFIED BY 'password';
-- FLUSH PRIVILEGES;

-- Set default character set
ALTER DATABASE auth_service_development CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE auth_service_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE auth_service_production CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Set MySQL configuration for optimal Rails performance
SET GLOBAL max_connections = 500;
SET GLOBAL wait_timeout = 600;
SET GLOBAL interactive_timeout = 600;

-- Enable slow query log for debugging
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Show current configuration
SHOW VARIABLES LIKE 'max_connections';
SHOW VARIABLES LIKE 'character_set%';
SHOW VARIABLES LIKE 'collation%';
