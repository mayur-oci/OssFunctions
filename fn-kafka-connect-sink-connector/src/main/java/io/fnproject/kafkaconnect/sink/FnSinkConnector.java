package io.fnproject.kafkaconnect.sink;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.Task;
import org.apache.kafka.connect.sink.SinkConnector;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.*;

public class FnSinkConnector extends SinkConnector {
    private Map<String, String> configProperties;

    @Override
    public void start(Map<String, String> config) {
        this.configProperties = config;
        new Thread(new StartOciFunctionProcessThread()).start();
    }


    @Override
    public Class<? extends Task> taskClass() {
        return FnInvocationTask.class;
    }

    @Override
    public List<Map<String, String>> taskConfigs(int numOfMaxTasks) {
        System.out.println("Max Tasks is : " + numOfMaxTasks);

        List<Map<String, String>> taskConfigs = new ArrayList<>();
        Map<String, String> properties = new HashMap<>();
        properties.putAll(configProperties);
        for (int i = 0; i < numOfMaxTasks; i++) {
            taskConfigs.add(properties);
        }
        System.out.println("Task configuration complete..");
        return taskConfigs;
    }

    @Override
    public void stop() {
        System.out.println("Connector stopped");
    }

    @Override
    public ConfigDef config() {
        System.out.println("Fetching connector config");
        return FnInvocationConfig.getConfigDef();
    }

    @Override
    public String version() {
        return "v1.0";
    }

    class StartOciFunctionProcessThread implements Runnable{

        @Override
        public void run() {
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
                env.putAll(configProperties);
                if (configProperties.get("ociLocalConfig") == null || configProperties.get("ociLocalConfig").length() == 0) {
                    env.remove("ociLocalConfig");
                }

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
        }
    }

}
