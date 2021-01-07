package io.fnproject.kafkaconnect.sink;

import com.google.gson.Gson;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.connect.sink.SinkRecord;
import org.apache.kafka.connect.sink.SinkTask;
import org.zeromq.SocketType;
import org.zeromq.ZContext;
import org.zeromq.ZMQ;

import java.util.Collection;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

public class FnInvocationTask extends SinkTask {
    ZContext zcontext = null;
    ZMQ.Socket socket = null;
    private Map<String, String> config;
    static AtomicInteger processedReviews = new AtomicInteger(0);

    @Override
    public void start(Map<String, String> config) {
        this.config = config;
        System.out.println("Task started with config... " + config);

        try {
            zcontext = new ZContext();
            socket = zcontext.createSocket(SocketType.REQ);
            socket.connect("tcp://localhost:5555");
        } catch (Exception e) {
            e.printStackTrace();
        }
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
                this.sendZmqMessage(json);
                processedReviews.incrementAndGet();
                System.out.println("Count of reviews processed so far:"+processedReviews);
            }
        }
    }


    private synchronized void sendZmqMessage(String review) {
        try {
            //System.out.println("Sending review " + review);
            socket.send(review.getBytes(ZMQ.CHARSET), 0);
            byte[] reply = socket.recv(0);
            System.out.println("Received -> " + new String(reply, ZMQ.CHARSET) + " for review -> " + review);
        } catch (Exception e) {
            System.out.println("Error in sendZmqMessage " + e);
        }
    }

    @Override
    public void stop() {
        System.out.println("FnSink Task stopped... total count for reviews processed is "+ processedReviews);
    }

    @Override
    public String version() {
        System.out.println("Getting FnSink Task version...");
        return "v1.0";
    }

}
