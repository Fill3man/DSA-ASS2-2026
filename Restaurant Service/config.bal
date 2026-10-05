// Defaults are for `bal run` on the host; docker-compose.yml overrides
// them with BAL_CONFIG_VAR_* environment variables.

configurable int port = 8082;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://restaurant_svc:dev-service-pass@localhost:27017/restaurant_db?authSource=restaurant_db";
configurable string mongoDatabase = "restaurant_db";

const SERVICE_NAME = "restaurant-service";
