// Defaults are for `bal run` on the host; docker-compose.yml overrides
// them with BAL_CONFIG_VAR_* environment variables.

configurable int port = 8084;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://payment_svc:dev-service-pass@localhost:27017/payment_db?authSource=payment_db";
configurable string mongoDatabase = "payment_db";

const SERVICE_NAME = "payment-service";
