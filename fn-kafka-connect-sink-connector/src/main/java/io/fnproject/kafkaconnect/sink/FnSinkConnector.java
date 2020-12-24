package io.fnproject.kafkaconnect.sink;

import org.apache.kafka.common.config.ConfigDef;
import org.apache.kafka.connect.connector.Task;
import org.apache.kafka.connect.sink.SinkConnector;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.*;

public class FnSinkConnector extends SinkConnector {
    private Map<String, String> configProperties;

    private OciFnProcessTracker ociFnProcessTracker = null;

    @Override
    public void start(Map<String, String> config) {
        this.configProperties = config;
        OciFnProcessTracker ociFnProcessTracker = new OciFnProcessTracker();
        new Thread(new OciFnProcessTracker()).start();
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
        ociFnProcessTracker.stop();
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

    class OciFnProcessTracker implements Runnable {
        Process p = null;

        @Override
        public void run() {
            try {
                launchProcess();
                trackOutput();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        private void trackOutput() throws IOException {
            System.out.println("Started OciFnSDK");
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(p.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    System.out.println("fnprocess o/p :: " + line);
                    if (!p.isAlive()) break;
                }
            }
            System.out.println("fnprocess process exit value is " + p.exitValue());
        }

        private void launchProcess() throws IOException {
            String javaHome = System.getProperty("java.home");
            String javaBin = javaHome +  File.separator + "bin" + File.separator + "java";

            List<String> command = new LinkedList<String>();
            command.add(javaBin); command.add("-jar");
            String jarPath = "/usr/fnprocess/fnprocess-1.0-SNAPSHOT-jar-with-dependencies.jar";
            command.add(jarPath);

            ProcessBuilder pb = new ProcessBuilder(command);
            Map<String, String> env = pb.environment();
            putFunctionInfoInEnv(env);

            p = pb.start();
        }

        private void putFunctionInfoInEnv(Map<String, String> env) {
            env.clear();
            env.put(FnInvocationConfig.OCI_REGION_FOR_FUNCTION, configProperties.get(FnInvocationConfig.OCI_REGION_FOR_FUNCTION));
            env.put(FnInvocationConfig.OCI_COMPARTMENT_ID_FOR_FUNCTION, configProperties.get(FnInvocationConfig.OCI_COMPARTMENT_ID_FOR_FUNCTION));
            env.put(FnInvocationConfig.FUNCTION_APP_NAME, configProperties.get(FnInvocationConfig.FUNCTION_APP_NAME));
            env.put(FnInvocationConfig.FUNCTION_NAME, configProperties.get(FnInvocationConfig.FUNCTION_NAME));
            if (!(configProperties.get(FnInvocationConfig.OCI_LOCAL_CONFIG) == null) &&
                    !(configProperties.get(FnInvocationConfig.OCI_LOCAL_CONFIG).length() == 0)) {
                env.put(FnInvocationConfig.OCI_LOCAL_CONFIG, configProperties.get(FnInvocationConfig.OCI_LOCAL_CONFIG));
            }
        }

        void stop() {
            p.destroy();
        }

    }

}
