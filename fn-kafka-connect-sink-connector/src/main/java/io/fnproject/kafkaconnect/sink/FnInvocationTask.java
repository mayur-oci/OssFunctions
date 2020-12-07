package io.fnproject.kafkaconnect.sink;

import com.google.gson.Gson;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.connect.sink.SinkRecord;
import org.apache.kafka.connect.sink.SinkTask;

import java.util.Collection;
import java.util.Map;

public class FnInvocationTask extends SinkTask {
    private Map<String, String> config;

    @Override
    public void start(Map<String, String> config) {
        this.config = config;
        OciFunction.initialize(config);
        System.out.println("Task started with config... " + config);
    }

    @Override
    public void open(Collection<TopicPartition> partitions) {
        super.open(partitions);
        this.context.assignment().stream()
                .forEach((tp) -> System.out.println("Task assigned partition " + tp.partition() + " in topic " + tp.topic()));
    }

    @Override
    public void put(Collection<SinkRecord> records) {
        System.out.println("No. of records " + records.size());

        for (SinkRecord record : records) {
            System.out.println("Got record from offset " + record.kafkaOffset()
                    + " in partition " + record.kafkaPartition() + " of topic " + record.topic());
            if (record.key() != null)
                System.out.println("Key type is :" + record.key().getClass().getCanonicalName());
            if (record.value() != null) {
                System.out.println("Value type is :" + record.value().getClass().getCanonicalName());
                System.out.println("Message with value:->  " + record.value());
                Gson gson = new Gson();
                String json = gson.toJson(record.value());
                OciFunction.invokeFunction(json);
            }
        }
    }


    @Override
    public void stop() {
        OciFunction.closeFn();
        System.out.println("FnSink Task stopped... ");
    }

    @Override
    public String version() {
        System.out.println("Getting FnSink Task version...");
        return "v1.0";
    }

}
