// Defaults are for `bal run` on the host; docker-compose.yml overrides
// them with BAL_CONFIG_VAR_* environment variables.

configurable int port = 8087;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://admin_svc:dev-service-pass@localhost:27017/admin_db?authSource=admin_db";
configurable string mongoDatabase = "admin_db";

const SERVICE_NAME = "admin-service";
