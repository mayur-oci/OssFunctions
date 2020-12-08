# This script needs root privileges
    sudo bash

# Disable firewall of OCI linux node for HTTP and other communication to node
    sestatus
    setenforce 0
    search='SELINUX=enforcing'
    replace='SELINUX=disabled'
    sed -i "s/${search}/${replace}/g" /etc/selinux/config # Note the double quotes
    systemctl stop firewalld
    systemctl disable firewalld

# Upgrade yum package manager
    yum upgrade -y -q

# Install git for fetching the code
    yum install -y git

# Run dockerized Kafka Connector framework. Note we have yet not configured the FnSinkConnector worker.
    OCI_STREAM_USERNAME="$OCI_TENANCY_NAME/$OCI_USER_ID/$OCI_STREAM_POOL_ID"
    KAFKA_SASL_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"${OCI_STREAM_USERNAME}\" password=\"${OCI_USER_AUTH_TOKEN}\";"
    HOST_IPv4=$(curl ifconfig.me)
    echo my ip address is $HOST_IPv4

    FILE=$HOME/.oci
    if [ -d "$FILE" ]; then
      echo "Local oci configs exist..hence will mount it in Kafka Connect Container"
      MOUNT_OCI_CONFIGS_IF_APPLICABLE="-v $HOME:$HOME"
    else
      echo "Local oci configs do not exist..hence will use dynamic groups"
      MOUNT_OCI_CONFIGS_IF_APPLICABLE=""
    fi

    git clone https://github.com/mayur-oci/OssFunctions
    cd ./OssFunctions/'fn-kafka-connect-sink-connector'
    ./mvnw  install

    docker build -t kafka-connect-fn-sink .

    docker run  --rm -it \
      --name=KafkaConnect \
      -p 8082:8082 \
      -p 9092:9092 \
      -e CONNECT_BOOTSTRAP_SERVERS=cell-1.streaming.us-phoenix-1.oci.oraclecloud.com:9092 \
      -e CONNECT_REST_PORT=8082 \
      -e CONNECT_GROUP_ID="newCG100_abc" \
      -e CONNECT_CONFIG_STORAGE_TOPIC="$CONNECT_HARNESS_OCID-config" \
      -e CONNECT_OFFSET_STORAGE_TOPIC="$CONNECT_HARNESS_OCID-offset" \
      -e CONNECT_STATUS_STORAGE_TOPIC="$CONNECT_HARNESS_OCID-status" \
      -e CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
      -e CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
      -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
      -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
      -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=false \
      -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=false \
      -e CONNECT_LOG4J_ROOT_LOGLEVEL="INFO" \
      -e CONNECT_PLUGIN_PATH=/usr/share/java/kafka-connect/ -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1 -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1 -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1 \
      -e CONNECT_SASL_MECHANISM=PLAIN \
      -e CONNECT_SECURITY_PROTOCOL=SASL_SSL \
      -e CONNECT_SASL_JAAS_CONFIG="${KAFKA_SASL_CONFIG}" \
      -e CONNECT_PRODUCER_SASL_MECHANISM=PLAIN \
      -e CONNECT_PRODUCER_SECURITY_PROTOCOL=SASL_SSL \
      -e CONNECT_PRODUCER_SASL_JAAS_CONFIG="${KAFKA_SASL_CONFIG}" \
      -e CONNECT_CONSUMER_SASL_MECHANISM=PLAIN \
      -e CONNECT_CONSUMER_SECURITY_PROTOCOL=SASL_SSL \
      -e CONNECT_CONSUMER_SASL_JAAS_CONFIG="${KAFKA_SASL_CONFIG}" \
      -e KAFKA_HEAP_OPTS="-Xms2024M -Xmx4G -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:9092" \
      ${MOUNT_OCI_CONFIGS_IF_APPLICABLE} \
      kafka-connect-fn-sink:latest



