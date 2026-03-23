# ============================================================
# Java Orchestrator — Multi-stage Docker Build
# ============================================================

# Stage 1: Build with Maven
FROM eclipse-temurin:21-jdk AS build
WORKDIR /app

COPY pom.xml .
# Download dependencies first (layer caching)
RUN apt-get update && apt-get install -y maven && rm -rf /var/lib/apt/lists/*
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn package -DskipTests -B

# Stage 2: Slim runtime
FROM eclipse-temurin:21-jre
WORKDIR /app

COPY --from=build /app/target/orchestrator-*.jar app.jar

# Support env var injection at runtime
ENV JAVA_OPTS=""
ENV SPRING_PROFILES_ACTIVE=demo

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar --spring.profiles.active=$SPRING_PROFILES_ACTIVE"]
