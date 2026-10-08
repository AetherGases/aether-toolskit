FROM eclipse-temurin:25-jdk
WORKDIR /src
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN chmod +x mvnw && ./mvnw -q -DskipTests package \
    && curl -fsSL "https://archive.apache.org/dist/tomcat/tomcat-11/v11.0.10/bin/apache-tomcat-11.0.10.tar.gz" \
      | tar -xz -C /opt \
    && mv /opt/apache-tomcat-11.0.10 /opt/tomcat \
    && rm -rf /opt/tomcat/webapps/* \
    && cp target/*.war /opt/tomcat/webapps/ROOT.war
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec /opt/tomcat/bin/catalina.sh run"]
