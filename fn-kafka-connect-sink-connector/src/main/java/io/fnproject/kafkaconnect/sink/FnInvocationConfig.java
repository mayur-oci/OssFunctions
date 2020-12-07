package io.fnproject.kafkaconnect.sink;

import org.apache.kafka.common.config.ConfigDef;

public final class FnInvocationConfig {

    static final String OCI_REGION_FOR_FUNCTION = "ociRegionForFunction";
    static final String OCI_COMPARTMENT_ID_FOR_FUNCTION = "ociCompartmentIdForFunction";
    static final String FUNCTION_APP_NAME = "functionAppName";
    static final String FUNCTION_NAME = "functionName";
    static final String OCI_LOCAL_CONFIG = "ociLocalConfig";


    public static ConfigDef getConfigDef() {
        return new ConfigDef()
                .define(OCI_REGION_FOR_FUNCTION, ConfigDef.Type.STRING, ConfigDef.Importance.HIGH, "OCI_REGION_FOR_FUNCTION")
                .define(OCI_COMPARTMENT_ID_FOR_FUNCTION, ConfigDef.Type.STRING, ConfigDef.Importance.HIGH, "OCI_COMPARTMENT_ID_FOR_FUNCTION")
                .define(FUNCTION_APP_NAME, ConfigDef.Type.STRING, ConfigDef.Importance.HIGH, "FUNCTION_APP_NAME")
                .define(FUNCTION_NAME, ConfigDef.Type.STRING, ConfigDef.Importance.HIGH, "FUNCTION_NAME")
                .define(OCI_LOCAL_CONFIG, ConfigDef.Type.STRING, ConfigDef.Importance.LOW, "OCI_LOCAL_CONFIG");
    }
}
