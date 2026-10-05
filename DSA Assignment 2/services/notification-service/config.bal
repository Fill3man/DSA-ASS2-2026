// Defaults are for `bal run` on the host; docker-compose.yml overrides
// them with BAL_CONFIG_VAR_* environment variables.

configurable int port = 8086;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://notification_svc:dev-service-pass@localhost:27017/notification_db?authSource=notification_db";
configurable string mongoDatabase = "notification_db";

const SERVICE_NAME = "notification-service";
