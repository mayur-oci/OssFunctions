package com.oci.demo.fn;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.oci.demo.review.pojo.ReviewReq;
import com.oracle.bmc.ConfigFileReader;
import com.oracle.bmc.Region;
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ConfigFileAuthenticationDetailsProvider;
import com.oracle.bmc.auth.ResourcePrincipalAuthenticationDetailsProvider;
import com.oracle.bmc.objectstorage.ObjectStorage;
import com.oracle.bmc.objectstorage.ObjectStorageClient;
import com.oracle.bmc.objectstorage.requests.PutObjectRequest;
import com.oracle.bmc.objectstorage.transfer.UploadConfiguration;
import com.oracle.bmc.objectstorage.transfer.UploadManager;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.util.Map;

class ObjectStorageHandler {
    static String ociObjectStorageNamespace = System.getenv().get("OCI_OBJECT_STORAGE_NAMESPACE");
    static String goodReviewsBucket = System.getenv().get("GOOD_REVIEWS_BUCKET_NAME");
    static String badReviewsBucket = System.getenv().get("BAD_REVIEWS_BUCKET_NAME");
    static String regionForBucket = System.getenv().get("OCI_OBJECT_STORAGE_REGION");

    static ObjectStorage client = ObjectStorageClient.builder().region(Region.fromRegionCodeOrId(regionForBucket)).
            build(getOciAuthProvider());

    static Map<String, String> metadata = null;
    static String contentType = null;
    static String contentEncoding = null;
    static String contentLanguage = null;

    // configure upload settings as desired
    static UploadConfiguration uploadConfiguration =
            UploadConfiguration.builder()
                    .allowMultipartUploads(false)
                    .allowParallelUploads(false)
                    .build();

    static UploadManager uploadManager = new UploadManager(client, uploadConfiguration);
    static ObjectMapper objectMapper = new ObjectMapper();

    static private void putReviewObject(boolean isItGoodReview, File logFileObj) {

        PutObjectRequest request =
                PutObjectRequest.builder()
                        .bucketName(isItGoodReview ? goodReviewsBucket : badReviewsBucket)
                        .namespaceName(ociObjectStorageNamespace)
                        .objectName(logFileObj.getName())
                        .contentType(contentType)
                        .contentLanguage(contentLanguage)
                        .contentEncoding(contentEncoding)
                        .opcMeta(metadata)
                        .build();

        UploadManager.UploadRequest uploadDetails =
                UploadManager.UploadRequest.builder(logFileObj).allowOverwrite(true).build(request);

        UploadManager.UploadResponse response = uploadManager.upload(uploadDetails);
    }

    static boolean uploadReview(boolean isItGoodReview, ReviewReq review) {
        System.err.println(" In the uploadReview function ");

        try {
            String longCurr = Long.toString(System.currentTimeMillis());
            String randomEnd = longCurr.substring(longCurr.length() - 4, longCurr.length());
            File tempFile = new File("/tmp/" + review.getProductId() + "_" + randomEnd + ".json");
            if (tempFile.exists()) {
                tempFile.delete();
            }
            Files.write(tempFile.toPath(),
                    objectMapper.writerWithDefaultPrettyPrinter().
                            writeValueAsString(review).getBytes(), StandardOpenOption.CREATE);
            putReviewObject(isItGoodReview, tempFile);
            tempFile.delete();
            return true;
        } catch (Exception e) {
            System.err.println("Exception in uploadReview " + e);
            return false;
        }
    }

    // OCI Auth provider is needed for accessing Object Storage
    private static BasicAuthenticationDetailsProvider getOciAuthProvider() {
        String version = System.getenv("OCI_RESOURCE_PRINCIPAL_VERSION");
        BasicAuthenticationDetailsProvider provider = null;
        if (version != null) {
            provider = ResourcePrincipalAuthenticationDetailsProvider.builder().build();
        } else {
            try {
                // for local dev/testing
                // the user profile you choose here must belong to a group with these Authorizations in a policy, unless the user is Admin
                File file = new File("/Users/mraleras/.oci/config");
                final ConfigFileReader.ConfigFile configFile;
                configFile = ConfigFileReader.parse(file.getAbsolutePath(), "DEFAULT");
                provider = new ConfigFileAuthenticationDetailsProvider(configFile);
            } catch (IOException ioException) {
                ioException.printStackTrace();
            }
        }
        return provider;
    }

}

