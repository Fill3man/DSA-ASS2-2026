// Defaults are for `bal run` on the host; docker-compose.yml overrides
// them with BAL_CONFIG_VAR_* environment variables.

configurable int port = 8085;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://delivery_svc:dev-service-pass@localhost:27017/delivery_db?authSource=delivery_db";
configurable string mongoDatabase = "delivery_db";

const SERVICE_NAME = "delivery-service";
