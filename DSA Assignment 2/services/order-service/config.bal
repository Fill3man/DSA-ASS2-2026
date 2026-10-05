// Configurable values. Defaults are for running on the host against the
// docker-compose infrastructure; docker-compose.yml overrides them with
// BAL_CONFIG_VAR_* environment variables inside the container network.

configurable int port = 8083;
configurable string kafkaBootstrap = "localhost:9092";
configurable string mongoUri = "mongodb://order_svc:dev-service-pass@localhost:27017/order_db?authSource=order_db";
configurable string mongoDatabase = "order_db";
configurable string currency = "NAD";

// How many times an incoming event is retried before it is sent to orders.dlq.
configurable int maxEventRetries = 3;
