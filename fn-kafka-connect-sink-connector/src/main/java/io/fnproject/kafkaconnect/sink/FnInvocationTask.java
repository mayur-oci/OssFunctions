package io.fnproject.kafkaconnect.sink;

import com.google.gson.Gson;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.connect.sink.SinkRecord;
import org.apache.kafka.connect.sink.SinkTask;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.Collection;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

public class FnInvocationTask extends SinkTask {
    private Map<String, String> config;

    @Override
    public void start(Map<String, String> config) {
        this.config = config;
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
                this.invokeFnProcess(json);
            }
        }
    }


    private boolean invokeFnProcess(String review) {
        try {

            String javaHome = System.getProperty("java.home");
            String javaBin = javaHome +
                    File.separator + "bin" +
                    File.separator + "java";

            List<String> command = new LinkedList<String>();
            command.add(javaBin);
            command.add("-jar");
            String jarPath = "/usr/OciFnSdk/FnUtility-1.0-SNAPSHOT-jar-with-dependencies.jar";
            command.add(jarPath);

            ProcessBuilder pb = new ProcessBuilder(command);
            Map<String, String> env = pb.environment();
            env.clear();
            env.putAll(this.config);
            if (this.config.get("ociLocalConfig") == null || this.config.get("ociLocalConfig").length() == 0) {
                env.remove("ociLocalConfig");
            }
            env.put("review", review);

            Process p = pb.start();
            String outputFromProcess = "";
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    outputFromProcess = outputFromProcess + line + "\n";
                }
            }

            while (p.isAlive()) ;
            System.out.println("process exit value is " + p.exitValue());
            System.out.println("process exited with output:\n" + outputFromProcess);

        } catch (Exception e) {
            e.printStackTrace();
        }

        return true;
    }

    @Override
    public void stop() {
        System.out.println("FnSink Task stopped... ");
    }

    @Override
    public String version() {
        System.out.println("Getting FnSink Task version...");
        return "v1.0";
    }

}
