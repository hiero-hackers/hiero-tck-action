FROM eclipse-temurin:21-jdk AS builder

RUN apt-get update && apt-get install -y --no-install-recommends git

WORKDIR /app

COPY . .
RUN chmod +x ./gradlew
RUN ./gradlew assemble
RUN ./gradlew :tck:bootJar -x test -x spotlessCheck

FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=builder /app/tck/build/libs/*.jar app.jar
EXPOSE 8544

ENTRYPOINT ["java", "-jar", "app.jar"]
