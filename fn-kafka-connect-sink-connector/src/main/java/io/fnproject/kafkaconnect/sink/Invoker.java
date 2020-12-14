package io.fnproject.kafkaconnect.sink;

import java.io.File;
import java.lang.reflect.Method;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingDeque;

public class Invoker extends Thread {
    public static Invoker invoker;
    public BlockingQueue<String> blockingQueue = new LinkedBlockingDeque();
    Class<OciFunction> ociFunctionClass = null;
    ParentLastUrlClassLoader ccl = null;
    Map<String, String> config = null;

    public Invoker(Map<String, String> config) {
        try {
            ccl = new ParentLastUrlClassLoader(pluginDepsJars());
            this.setContextClassLoader(this.ccl);
            this.config = config;
            Invoker.invoker = this;
        } catch (Exception e) {
            System.out.println(" ERROR: error invoking init on OciFunctions " + e);
            e.printStackTrace();
            System.exit(1);
        }
    }

    private List<URL> pluginDepsJars() {
        List<URL> urls = new ArrayList<>();
        try {
            File dir = new File("/usr/FnSinkDependencies/");
            if (dir.isDirectory()) {
                for (File jar : dir.listFiles()) {
                    urls.add(jar.toURI().toURL());
                }
            }
            urls.add(new File("/usr/share/java/kafka-connect/" +
                    "fn-kafkaconnect-sink-connector-1.0.jar").toURI().toURL());
            return urls;
        } catch (Exception e) {
            System.out.println(" ERROR: urls for plugin dependencies failed " + e);
            // System.exit(1);
        }
        return null;
    }

    @Override
    public void run() {
        try {
            System.out.println(" started worker thread");

            Class<OciFunction> ociFunctionClass = (Class<OciFunction>) ccl.loadClass("io.fnproject.kafkaconnect.sink.OciFunction", true);
            Method m = ociFunctionClass.getDeclaredMethod("init", Map.class);
            m.setAccessible(true);
            m.invoke(null, config);


            while (true) {
                String reviewJson = this.blockingQueue.take();
                System.out.println(" about to invoke function for :" + reviewJson);
                Method invokeFunction = ociFunctionClass.getDeclaredMethod("invokeFunction", String.class);
                invokeFunction.setAccessible(true);
                invokeFunction.invoke(null, reviewJson);
                System.out.println(" Success: when reflectively invoking Functions ");
            }
        } catch (Exception e) {
            System.out.println("failed in run!!!! " + e);
            e.printStackTrace();
            // System.exit(1);
        }

    }
}
