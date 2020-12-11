package io.fnproject.kafkaconnect.sink;

import com.oracle.bmc.Region;
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

import java.nio.charset.StandardCharsets;
import java.util.Map;

public class OciFunction {

    private static Map<String, String> config;
    private static FunctionsInvokeClient fnInvokeClient = null;
    private static FunctionsManagementClient fnManagementClient = null;
    private static FunctionSummary fn = null;

    static void initialize(Map<String, String> connectorConfig) {
        try {
            config = connectorConfig;
            fnManagementClient =
                    new FunctionsManagementClient(IdentityOciProvider.provider);
            fnManagementClient.setRegion(Region.fromRegionCodeOrId(config.get(FnInvocationConfig.OCI_REGION_FOR_FUNCTION)));
            fnInvokeClient = new FunctionsInvokeClient(IdentityOciProvider.provider);

            fn = getUniqueFunctionByName(fnManagementClient, config.get(FnInvocationConfig.OCI_COMPARTMENT_ID_FOR_FUNCTION),
                    config.get(FnInvocationConfig.FUNCTION_APP_NAME), config.get(FnInvocationConfig.FUNCTION_NAME));
            fnInvokeClient.setEndpoint(fn.getInvokeEndpoint());
            System.out.println("OciFunction initialize success.");
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

    static boolean invokeFunction(String payload) {
        try {
            System.out.println("Invoking function endpoint - " + fn.getInvokeEndpoint());

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
            if (response != null) {
                System.out.println("Response from function:  " + response);
            }
            return true;
        } catch (final Exception e) {
            e.printStackTrace();
            System.out.println("Failed to invoke function: " + e);
            return false;
        }
    }

    static void closeFn() {
        fnInvokeClient.close();
        fnManagementClient.close();
    }


}
