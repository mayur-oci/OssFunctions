package io.fnproject.kafkaconnect.sink;

import com.oracle.bmc.ConfigFileReader;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.InstancePrincipalsAuthenticationDetailsProvider;
import org.apache.commons.lang3.StringUtils;

import java.io.File;
import java.util.Map;

public class IdentityOciProvider {
    // OCI Auth provider is needed for accessing Object Storage
    static BasicAuthenticationDetailsProvider provider = null;

    static void initialize(Map<String, String> connectorConfig) {
        try {
            if (StringUtils.isNotEmpty(connectorConfig.get(FnInvocationConfig.OCI_LOCAL_CONFIG))) {
                String configFilePath = connectorConfig.get(FnInvocationConfig.OCI_LOCAL_CONFIG) + "/.oci/config";
                System.out.println("CONFIG_FILE_PATH:" + configFilePath);
                File file = new File(configFilePath);
                if (file.exists()) {
                    final ConfigFileReader.ConfigFile configFile = ConfigFileReader.parse(file.getAbsolutePath(), "DEFAULT");
                    provider = new ConfigFileAuthenticationDetailsProvider(configFile);
                    System.out.println(" Oci Config provider created: " + provider);
                    return;
                }
            }
        } catch (Exception e) {
            System.out.println(" Oci Config provider failed, will try instance provider ");
        }

        try {
            provider = InstancePrincipalsAuthenticationDetailsProvider.builder().build();
        } catch (Exception e) {
            System.out.println(" Oci Instance provider failed ");
        }

        return;
    }
}
