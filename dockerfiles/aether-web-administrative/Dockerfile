FROM eclipse-temurin:25-jdk
WORKDIR /src
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN if [ ! -f .mvn/wrapper/maven-wrapper.properties ]; then \
      mkdir -p .mvn/wrapper \
      && printf '%s\n' \
        'distributionUrl=https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.9/apache-maven-3.9.9-bin.zip' \
        'wrapperUrl=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.0/maven-wrapper-3.3.0.jar' \
        > .mvn/wrapper/maven-wrapper.properties; \
    fi \
    && if [ ! -f .mvn/wrapper/maven-wrapper.jar ]; then \
      curl -fsSL -o .mvn/wrapper/maven-wrapper.jar \
        https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.0/maven-wrapper-3.3.0.jar; \
    fi \
    && sed -i 's/\r$//' mvnw \
    && chmod +x mvnw && ./mvnw -q -DskipTests package \
    && curl -fsSL "https://archive.apache.org/dist/tomcat/tomcat-11/v11.0.10/bin/apache-tomcat-11.0.10.tar.gz" \
      | tar -xz -C /opt \
    && mv /opt/apache-tomcat-11.0.10 /opt/tomcat \
    && rm -rf /opt/tomcat/webapps/* \
    && cp target/*.war /opt/tomcat/webapps/ROOT.war \
    && mkdir -p /app
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "env > /app/.env && exec /opt/tomcat/bin/catalina.sh run"]