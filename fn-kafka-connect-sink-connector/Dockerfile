FROM confluentinc/cp-kafka-connect-base:6.0.0

# Copy connector JAR
RUN mkdir -p /usr/share/java/FnSinkConnector/
ENV CONNECTOR_JAR_PATH target/fn-kafkaconnect-sink-connector-1.0.jar
COPY $CONNECTOR_JAR_PATH /usr/share/java/FnSinkConnector/
