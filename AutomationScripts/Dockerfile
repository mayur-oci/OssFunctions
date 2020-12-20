FROM confluentinc/cp-kafka-connect-base:6.0.0


# Copy connector JAR
RUN mkdir -p /usr/share/java/kafka-connect/
COPY "fn-kafka-connect-sink-connector/target/fn-kafkaconnect-sink-connector-1.0.jar" /usr/share/java/kafka-connect/

USER root
RUN mkdir -p /usr/OciFnSdk/
COPY  --chown=appuser "OciFnSdk/target/FnUtility-1.0-SNAPSHOT-jar-with-dependencies.jar" /usr/OciFnSdk/
RUN chmod 777 /usr/OciFnSdk/*

