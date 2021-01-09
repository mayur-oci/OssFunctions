package io.fnproject.kafkaconnect.sink;

import org.zeromq.SocketType;
import org.zeromq.ZContext;
import org.zeromq.ZMQ;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

class OciFnProcessTracker implements Runnable {
    private Process p = null;
    private Map<String, String> configProperties;
    ZContext zcontext = null;
    ZMQ.Socket socket = null;

    public OciFnProcessTracker(Map<String, String> configProperties){
        this.configProperties = configProperties;
    }

    @Override
    public void run() {
        try {
            Optional<ProcessHandle> existingProcess = ProcessHandle
                    .allProcesses()
                    .filter(p -> p.info().commandLine().map(c -> c.contains("fnprocess-1.0-SNAPSHOT-jar-with-dependencies.jar")).orElse(false))
                    .findFirst();

            if (existingProcess.isPresent()){
                existingProcess.get().destroyForcibly();
                while (existingProcess.get().isAlive());
            }

            launchProcess();
            trackOutput();
            Thread.sleep(100); // wait for OciFnProcess to start zmq server

            zcontext = new ZContext();
            socket = zcontext.createSocket(SocketType.REQ);
            socket.connect("tcp://localhost:5555");
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

    synchronized void sendZmqMessage(String review) {
        try {
            //System.out.println("Sending review " + review);
            socket.send(review.getBytes(ZMQ.CHARSET), 0);
            byte[] reply = socket.recv(0);
            System.out.println("Received -> " + new String(reply, ZMQ.CHARSET) + " for review -> " + review);
        } catch (Exception e) {
            System.out.println("Error in sendZmqMessage " + e);
        }
    }

}

