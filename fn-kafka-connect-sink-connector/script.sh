mvn install

CONNECT_HARNESS_OCID='ocid1.connectharness.oc1.phx.amaaaaaauwpiejqamsosflwbo75cg4ft7bpgcglrlqd3mfbwmhhib6v6bd4q'
OCID_STREAM_POOL='ocid1.streampool.oc1.phx.amaaaaaauwpiejqactzuddgmegg42gkhwpz24wy6k7ka3n24nc52mpzqfvua'
OCI_USER_ID="mayur.raleraskar@oracle.com"
OCI_USER_AUTH_TOKEN="2m{s4WTCXysp:o]tGx4K"
OCI_STREAM_USERNAME="intrandallbarnes/$OCI_USER_ID/$OCID_STREAM_POOL"
KAFKA_SASL_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${OCI_STREAM_USERNAME}\" password=\"${OCI_USER_AUTH_TOKEN}\";"
OCI_STREAM_PARTITIONS_COUNT=1
CONNECT_REST_ADVERTISED_HOST_NAME=$(curl ifconfig.me)

docker build --build-arg PRIVATE_KEY_NAME=private_key.pem -t kafka-connect-fn-sink .

docker run --rm -it \
  --name=KafkaConnect \
  -p 8082:8082 \
  -p 9092:9092 \
  -e CONNECT_BOOTSTRAP_SERVERS=cell-1.streaming.us-phoenix-1.oci.oraclecloud.com:9092 \
  -e CONNECT_REST_PORT=8082 \
  -e CONNECT_GROUP_ID="newCG100_4" \
  -e CONNECT_CONFIG_STORAGE_TOPIC="$CONNECT_HARNESS_OCID-config" \
  -e CONNECT_OFFSET_STORAGE_TOPIC="$CONNECT_HARNESS_OCID-offset" \
  -e CONNECT_STATUS_STORAGE_TOPIC="$CONNECT_HARNESS_OCID-status" \
  -e CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_REST_ADVERTISED_HOST_NAME="localhost" \
  -e CONNECT_LOG4J_ROOT_LOGLEVEL="INFO" \
  -e CONNECT_PLUGIN_PATH=/usr/share/java/kafka-connect/ -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1 -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1 -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1 \
  -e \
  CONNECT_SASL_MECHANISM=PLAIN \
  -e CONNECT_SECURITY_PROTOCOL=SASL_SSL \
  -e CONNECT_SASL_JAAS_CONFIG="${KAFKA_SASL_CONFIG}" \
  -e CONNECT_PRODUCER_SASL_MECHANISM=PLAIN \
  -e CONNECT_PRODUCER_SECURITY_PROTOCOL=SASL_SSL \
  -e CONNECT_PRODUCER_SASL_JAAS_CONFIG="${KAFKA_SASL_CONFIG}" \
  -e CONNECT_CONSUMER_SASL_MECHANISM=PLAIN \
  -e CONNECT_CONSUMER_SECURITY_PROTOCOL=SASL_SSL \
  -e CONNECT_CONSUMER_SASL_JAAS_CONFIG="${KAFKA_SASL_CONFIG}" \
  -e KAFKA_HEAP_OPTS="-Xms2024M -Xmx4G -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:9092" \
  -v /Users/mraleras/.oci:/oci \
  -v /Users/mraleras/IdeaProjects/fn-kafka-connect-sink-connector/ConnectLogDir:/logDir \
  kafka-connect-fn-sink:latest

exit
sleep 5

OCI_CURRENT_REGION=us-phoenix-1
FN_APP_NAME=fn_oss_app_test
OCI_STREAM_PARTITIONS_COUNT=1
OCI_STREAM_NAME=testnew
OCI_CMPT_OCID=xyz
FN_CONSUMER_FUNCTION_NAME=reviewConsumerFn

curl -X POST \
  http://localhost:8082/connectors \
  -H 'content-type: application/json' \
  -d "{
  \"name\": \"FnSinkConnector30\",
  \"config\": {
    \"connector.class\": \"io.fnproject.kafkaconnect.sink.FnSinkConnector\",
    \"tasks.max\": \"${OCI_STREAM_PARTITIONS_COUNT}\",
    \"topics\": \"${OCI_STREAM_NAME}\",
    \"ociRegionForFunction\": \"${OCI_CURRENT_REGION}\",
    \"ociCompartmentIdForFunction\": \"${OCI_CMPT_OCID}\",
    \"functionAppName\": \"${FN_APP_NAME}\",
    \"functionName\": \"${FN_APP_NAME}\"
  }
}"

# KAFKA_HEAP_OPTS
