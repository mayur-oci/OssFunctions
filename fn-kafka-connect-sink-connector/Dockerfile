FROM confluentinc/cp-kafka-connect-base:6.0.0

# Copy connector JAR
RUN mkdir -p /usr/share/java/kafka-connect
ENV CONNECTOR_JAR_PATH target/fn-kafkaconnect-sink-connector-1.0.jar
COPY $CONNECTOR_JAR_PATH /usr/share/java/kafka-connect/

# Copy OCI user private key
#ARG LOCAL_DEV_ENV
#RUN if [ "x$LOCAL_DEV_ENV" = "true" ] ; then
#       echo local dev env hence copying oci profile files ;
#       RUN mkdir -p /oci
#    else
#       echo Argument is $arg ;
#    fi