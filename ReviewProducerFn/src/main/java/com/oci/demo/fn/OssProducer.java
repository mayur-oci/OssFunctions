package com.oci.demo.fn;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.oci.demo.review.pojo.ReviewReq;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;

import java.util.Properties;
import java.util.UUID;


public class OssProducer {
    static String bootstrapServers = System.getenv().get("OCI_OSS_KAFKA_BOOTSTRAP_SERVERS");
    static String tenancyName = System.getenv().get("OCI_FN_TENANCY");
    static String username = System.getenv().get("OCI_USER_ID");
    static String streamPoolId = System.getenv().get("STREAM_POOL_OCID");
    static String authToken = System.getenv().get("OCI_AUTH_TOKEN");
    static String streamOrKafkaTopicName = System.getenv().get("REVIEWS_STREAM_OR_TOPIC_NAME");
    static ObjectMapper objectMapper = new ObjectMapper();

    public static boolean producer(ReviewReq review) {
        try {
            Properties properties = getKafkaOssProperties();
            KafkaProducer producer = new KafkaProducer<>(properties);

            ProducerRecord<String, String> record = new ProducerRecord<>(streamOrKafkaTopicName, UUID.randomUUID().toString(), objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(review));
            producer.send(record, (md, ex) -> {
                if (ex != null) {
                    System.err.println("exception occurred in producer for review :" + record.value()
                            + ", exception is " + ex);
                    ex.printStackTrace();
                } else {
                    System.err.println("Sent msg to " + md.partition() + " with offset " + md.offset() + " at " + md.timestamp());
                }
            });
            producer.flush();
            producer.close();
        } catch (Exception e) {
            System.err.println("Error: exception " + e);
            return false;
        }

        return true;
    }

    private static Properties getKafkaOssProperties() {
        setDefaultConfigsIfNeeded();
        Properties properties = new Properties();
        properties.put("bootstrap.servers", bootstrapServers);
        properties.put("security.protocol", "SASL_SSL");
        properties.put("sasl.mechanism", "PLAIN");
        properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());

        final String value = "org.apache.kafka.common.security.plain.PlainLoginModule required username=\""
                + tenancyName + "/"
                + username + "/"
                + streamPoolId + "\" "
                + "password=\""
                + authToken + "\";";
        properties.put("sasl.jaas.config", value);
        properties.put("retries", 5); // retries on transient errors and load balancing disconnection
        properties.put("max.request.size", 1024 * 1024); // limit request size to 1MB
        return properties;
    }

    private static void setDefaultConfigsIfNeeded() {
        tenancyName = tenancyName == null ? "intrandallbarnes" : tenancyName;
        username = username == null ? "mayur.raleraskar@oracle.com" : username;
        streamPoolId = streamPoolId == null ? "ocid1.streampool.oc1.phx.amaaaaaauwpiejqactzuddgmegg42gkhwpz24wy6k7ka3n24nc52mpzqfvua" : streamPoolId;
        streamOrKafkaTopicName = streamOrKafkaTopicName == null ? "testnew" : streamOrKafkaTopicName;
        authToken = authToken == null ? "2m{s4WTCXysp:o]tGx4K" : authToken;
        bootstrapServers = bootstrapServers == null ? "streaming.us-phoenix-1.oci.oraclecloud.com:9092" : bootstrapServers;
    }

    public boolean handleRequest(ReviewReq msg) {
        return producer(msg);
    }

}