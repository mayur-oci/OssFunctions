package oci.fnsdk.wrapper;

import com.oracle.bmc.ConfigFileReader;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import com.oracle.bmc.functions.FunctionsInvokeClient;
import com.oracle.bmc.functions.FunctionsManagementClient;
import com.oracle.bmc.functions.model.ApplicationSummary;
import com.oracle.bmc.functions.model.FunctionSummary;
import com.oracle.bmc.functions.requests.InvokeFunctionRequest;
import com.oracle.bmc.functions.requests.ListApplicationsRequest;
import com.oracle.bmc.functions.requests.ListFunctionsRequest;
import com.oracle.bmc.functions.responses.InvokeFunctionResponse;
import com.oracle.bmc.functions.responses.ListApplicationsResponse;
import com.oracle.bmc.functions.responses.ListFunctionsResponse;
import com.oracle.bmc.util.StreamUtils;
import org.apache.commons.io.IOUtils;
import org.apache.commons.lang3.StringUtils;
import org.zeromq.SocketType;
import org.zeromq.ZContext;
import org.zeromq.ZMQ;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Set;

public class OciFunction {
    static final String OCI_REGION_FOR_FUNCTION = "ociRegionForFunction";
    static final String OCI_COMPARTMENT_ID_FOR_FUNCTION = "ociCompartmentIdForFunction";
    static final String FUNCTION_APP_NAME = "functionAppName";
    static final String FUNCTION_NAME = "functionName";
    static final String OCI_LOCAL_CONFIG = "ociLocalConfig";

    private static Map<String, String> config;
    private static FunctionsInvokeClient fnInvokeClient = null;
    private static FunctionsManagementClient fnManagementClient = null;
    private static FunctionSummary fn = null;


    public static void main(String args[]) {
        config = System.getenv();
        Set<Map.Entry<String, String>> entrySet = config.entrySet();
        for (Map.Entry<String, String> entry : entrySet)
          { System.out.println("Key - " + entry.getKey() + ", Value - " + entry.getValue()); }
        init();
        zmqHandler();
    }

    static void zmqHandler() {
        try {
            //  Socket to talk to clients
            ZContext context = new ZContext();
            ZMQ.Socket socket = context.createSocket(SocketType.REP);
            socket.bind("tcp://*:5555");

            while (!Thread.currentThread().isInterrupted()) {
                byte[] reply = socket.recv(0);
                long startTime = System.currentTimeMillis();
                String review = new String(reply, ZMQ.CHARSET);
                System.out.println("Received for processing " + ": [" + new String(reply, ZMQ.CHARSET) + "]");
                String response = invokeFunction(review);
                if ("true".equals(response)) {
                    System.out.println("Success from function call, time taken in millis: " + (System.currentTimeMillis() - startTime));
                }else{
                    System.out.println("Failure from function call, time taken in millis: " + (System.currentTimeMillis() - startTime));
                }
                socket.send(response.getBytes(ZMQ.CHARSET), 0);
            }
        } catch (Exception e) {
            System.out.println(" Exception in zmqHandler:: " + e);
        }
    }


    static void init() {
        try {
            IdentityOciProvider.initialize(config);

            fnManagementClient =
                    new FunctionsManagementClient(IdentityOciProvider.provider);
            fnManagementClient.setRegion(Region.fromRegionCodeOrId(config.get(OCI_REGION_FOR_FUNCTION)));
            fnInvokeClient = new FunctionsInvokeClient(IdentityOciProvider.provider);

            fn = getUniqueFunctionByName(fnManagementClient, config.get(OCI_COMPARTMENT_ID_FOR_FUNCTION),
                    config.get(FUNCTION_APP_NAME), config.get(FUNCTION_NAME));
            fnInvokeClient.setEndpoint(fn.getInvokeEndpoint());
            System.out.println("OciFunction initialize success, function invoke endpoint:"+fn.getInvokeEndpoint());
        } catch (Exception e) {
            e.printStackTrace();
            System.out.println("OciFunction initialize failed : " + e);
        }
    }


    private static FunctionSummary getUniqueFunctionByName(
            final FunctionsManagementClient fnManagementClient,
            final String compartmentId,
            final String applicationDisplayName,
            final String functionDisplayName)
            throws Exception {
        final ApplicationSummary application =
                getUniqueApplicationByName(fnManagementClient, compartmentId, applicationDisplayName);
        return getUniqueFunctionByName(
                fnManagementClient, application.getId(), functionDisplayName);
    }

    private static FunctionSummary getUniqueFunctionByName(
            final FunctionsManagementClient fnManagementClient,
            final String applicationId,
            final String functionDisplayName)
            throws Exception {

        final ListFunctionsRequest listFunctionsRequest =
                ListFunctionsRequest.builder()
                        .applicationId(applicationId)
                        .displayName(functionDisplayName)
                        .build();

        final ListFunctionsResponse listFunctionsResponse =
                fnManagementClient.listFunctions(listFunctionsRequest);

        if (listFunctionsResponse.getItems().size() != 1) {
            throw new Exception(
                    "Could not find function with name "
                            + functionDisplayName
                            + " in application "
                            + applicationId);
        }

        return listFunctionsResponse.getItems().get(0);
    }

    public static ApplicationSummary getUniqueApplicationByName(
            final FunctionsManagementClient fnManagementClient,
            final String compartmentId,
            final String applicationDisplayName)
            throws Exception {

        // Find the application in a specific compartment
        final ListApplicationsRequest listApplicationsRequest =
                ListApplicationsRequest.builder()
                        .displayName(applicationDisplayName)
                        .compartmentId(compartmentId)
                        .build();

        final ListApplicationsResponse resp =
                fnManagementClient.listApplications(listApplicationsRequest);

        if (resp.getItems().size() != 1) {
            throw new Exception(
                    "Could not find unique application with name "
                            + applicationDisplayName
                            + " in compartment "
                            + compartmentId);
        }

        final ApplicationSummary application = resp.getItems().get(0);
        return application;
    }

    static String invokeFunction(String payload) {
        try {
            // Configure the client to use the assigned function endpoint.
            final InvokeFunctionRequest invokeFunctionRequest =
                    InvokeFunctionRequest.builder()
                            .functionId(fn.getId())
                            .invokeFunctionBody(
                                    StreamUtils.createByteArrayInputStream(payload.getBytes()))
                            .build();

            // Invoke the function!
            final InvokeFunctionResponse invokeFunctionResponse =
                    fnInvokeClient.invokeFunction(invokeFunctionRequest);

            // Handle the response.
            String response = IOUtils.toString(invokeFunctionResponse.getInputStream(), StandardCharsets.UTF_8);

            return response;
        } catch (final Exception e) {
            e.printStackTrace();
            System.out.println("Failed to invoke function: " + e);
            return "false";
        }
    }

    static void closeFn() {
        fnInvokeClient.close();
        fnManagementClient.close();
    }

    private static class IdentityOciProvider {
        // OCI Auth provider is needed for accessing Object Storage
        static BasicAuthenticationDetailsProvider provider = null;

        static void initialize(Map<String, String> connectorConfig) {
            try {
                if (StringUtils.isNotEmpty(connectorConfig.get(OCI_LOCAL_CONFIG))) {
                    String configFilePath = connectorConfig.get(OCI_LOCAL_CONFIG) + "/.oci/config";
                    System.out.println("CONFIG_FILE_PATH:" + configFilePath);
                    File file = new File(configFilePath);
                    if (file.exists()) {
                        final ConfigFileReader.ConfigFile configFile = ConfigFileReader.parse(file.getAbsolutePath(), "DEFAULT");
                        provider = new ConfigFileAuthenticationDetailsProvider(configFile);
                        System.out.println("Oci Config provider created: " + provider);
                        return;
                    }
                }
            } catch (Exception e) {
                System.out.println("Oci Config provider failed, will try instance provider ");
            }

            try {
                provider = InstancePrincipalsAuthenticationDetailsProvider.builder().build();
                System.out.println("Oci Instance provider success ");
            } catch (Exception e) {
                System.out.println("Oci Instance provider failed ");
            }

            return;
        }
    }

}

