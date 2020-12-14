FROM confluentinc/cp-kafka-connect-base:6.0.0


# Copy connector JAR
ENV CONNECTOR_JAR_PATH target
RUN mkdir -p /usr/share/java/kafka-connect/
COPY $CONNECTOR_JAR_PATH/fn-kafkaconnect-sink-connector-1.0.jar /usr/share/java/kafka-connect/

USER root
ENV CONNECTOR_JAR_PATH target
RUN mkdir -p /usr/FnSinkDependencies/
COPY  --chown=appuser $CONNECTOR_JAR_PATH/fn-kafkaconnect-sink-connector-1.0.lib/* /usr/FnSinkDependencies/
RUN chmod 777 /usr/FnSinkDependencies/*

