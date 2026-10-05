// Defaults are for `bal run` on the host; docker-compose.yml overrides
// them with BAL_CONFIG_VAR_* environment variables.

configurable int port = 8081;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://customer_svc:dev-service-pass@localhost:27017/customer_db?authSource=customer_db";
configurable string mongoDatabase = "customer_db";

const SERVICE_NAME = "customer-service";
