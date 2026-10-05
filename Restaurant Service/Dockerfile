# Build the jar first:  bal build   (or scripts/build-all.ps1 for every service)
FROM eclipse-temurin:21-jre

RUN groupadd --system app && useradd --system --gid app --no-create-home app
WORKDIR /app
COPY target/bin/restaurant_service.jar app.jar
USER app

EXPOSE 8082
HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -fsS http://localhost:8082/api/v1/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]