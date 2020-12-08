#!/bin/bash

#Pre-reqs oci cli, fn cli, java-8 and maven installed

#Basic tenancy and user information. User needs admin privileges.
          OCI_TENANCY_NAME=intrandallbarnes
          OCI_TENANCY_OCID=ocid1.tenancy.oc1..aaaaaaaaopbu45aomik7sswe4nzzll3f6ii6pipd5ttw4ayoozez37qqmh3a

          OCI_HOME_REGION=us-ashburn-1
          OCI_CURRENT_REGION=us-phoenix-1 # from OCI config file
          OCI_CURRENT_REGION_CODE=phx
          OCI_CMPT_NAME=cossfn1
          OCI_CLI_PROFILE=DEFAULT

#Create new compartment for this demo...We will create all resources for this demo inside this compartment.
          OCI_CMPT_ID=$(oci iam compartment create --name ${OCI_CMPT_NAME} --compartment-id ${OCI_TENANCY_OCID} \
                         --description "A compartment to fn oss integration" --region ${OCI_HOME_REGION} --query "data.id" --raw-output)
          echo Created compartment ${OCI_CMPT_NAME} with ID ${OCI_CMPT_ID}

#Create OCI streampool and stream(aka Kafka Topic) in it
          OCI_STREAM_POOL_NAME=REVIEWS_STREAM_POOL
          OCI_STREAM_NAME=REVIEWS_STREAM
          OCI_STREAM_PARTITIONS_COUNT=1
          OCI_STREAM_POOL_ID=$(oci streaming admin stream-pool create -c ${OCI_CMPT_ID} --name ${OCI_STREAM_POOL_NAME} --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_STREAM_ID=$(oci streaming admin stream create --name ${OCI_STREAM_NAME} --partitions ${OCI_STREAM_PARTITIONS_COUNT} --stream-pool-id ${OCI_STREAM_POOL_ID} --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_CONNECT_HARNESS_ID=$(oci streaming admin connect-harness create --region ${OCI_CURRENT_REGION} -c ${OCI_CMPT_ID} --name ConnectHarnessForFnSink --wait-for-state ACTIVE --query "data.id" --raw-output)

#Create buckets for processed reviews
          GOOD_REVIEW_BUCKET_NAME=GoodReviewsBucket
          BAD_REVIEWS_BUCKET_NAME=BadReviewsBucket
          GOOD_REVIEWS_BUCKET_OCID=$(oci os bucket create --name ${GOOD_REVIEW_BUCKET_NAME} -c $OCI_CMPT_ID --region $OCI_CURRENT_REGION --raw-output --query "data.id")
          BAD_REVIEWS_BUCKET_OCID=$(oci os bucket create --name ${BAD_REVIEWS_BUCKET_NAME} -c $OCI_CMPT_ID --region $OCI_CURRENT_REGION --raw-output --query "data.id")

#Create Dynamic group and policy for your function
          MATCHING_RULE_FOR_FN_DG="ALL {resource.type = 'fnfunc', resource.compartment.id=$OCI_CMPT_ID}	"
          OCI_FN_DG_ID=$(oci --region $OCI_HOME_REGION iam dynamic-group create --description 'for_fns_in_cmpt' --name "fn_dg_$OCI_CMPT_NAME" --matching-rule "$MATCHING_RULE_FOR_FN_DG" --wait-for-state ACTIVE --query "data.id" --raw-output)

          FN_POLICY="[\"Allow dynamic-group "fn_dg_$OCI_CMPT_NAME" to manage all-resources in compartment $OCI_CMPT_NAME \"]"
          echo $FN_POLICY > statements.json
          OCI_FN_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "fn_dg_policy_$OCI_CMPT_NAME" --description "A policy for these functions" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE)
          echo Created policy "fn_dg_policy_$OCI_CMPT_NAME".  Use the command: \'oci iam policy get --policy-id "${OCI_FN_POLICY_ID}"\' if you want to view the policy.
          rm -rf statements.json

#Create Policy for allowing FaaS service(hence your function) to access
          # 1- docker repo for getting function code and
          # 2- subnets for running funnctions inside it. We will soon create functions
          FN_POLICY="[\"Allow service FaaS to read repos in tenancy\", \"Allow service FaaS to use virtual-network-family in compartment $OCI_CMPT_NAME\"]"
          echo $FN_POLICY > statements.json
          OCI_FN_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "FaaS_POLICY_$OCI_CMPT_NAME" --description "A policy for FaaS functions" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE)
          echo Created policy "FaaS_POLICY_$OCI_CMPT_NAME".  Use the command: \'oci iam policy get --policy-id "${OCI_FN_POLICY_ID}"\' if you want to view the policy.
          rm -rf statements.json

#Creating subnets for OCI functions and compute instance for Kafka FnSink Connector worker 
          # create VCN:
            echo Creating VCN. This may take a few seconds...
            OCI_FN_VCN_NAME=faas-demo-vcn
            OCI_FN_VCN_CIDR_BLOCK=10.0.0.0/16
            OCI_FN_VCN_SUBNET_1_CIDR_BLOCK=10.0.1.0/24
            OCI_FN_VCN_SUBNET_2_CIDR_BLOCK=10.0.2.0/24
            OCI_FN_VCN_SUBNET_3_CIDR_BLOCK=10.0.3.0/24
            n=0
            until [ $n -ge 6 ]; do
              echo oci network vcn create --cidr-block ${OCI_FN_VCN_CIDR_BLOCK} --compartment-id ${OCI_CMPT_ID} --display-name ${OCI_FN_VCN_NAME}
              OCI_FN_VCN_ID=$(oci network vcn create --cidr-block ${OCI_FN_VCN_CIDR_BLOCK} --compartment-id ${OCI_CMPT_ID} --display-name ${OCI_FN_VCN_NAME} --query "data.id" --raw-output) && break
              n=$(($n + 1))
              echo [create failed, trying again in 10 seconds...]
              sleep 10
            done

            if [ $n -eq 6 ]; then
              fail "Could not create VCN, exiting script!"
            else
              OCI_FN_VCN_ROUTE_TABLE_ID=$(oci network vcn get --vcn-id ${OCI_FN_VCN_ID} --query 'data."default-route-table-id"' --raw-output)
              OCI_FN_VCN_SECURITY_LIST_ID=$(oci network vcn get --vcn-id ${OCI_FN_VCN_ID} --query 'data."default-security-list-id"' --raw-output)
              echo Created VCN ${OCI_FN_VCN_NAME} with ID ${OCI_FN_VCN_ID}
            fi

          # create subnets:
            OCI_FN_SUBNET_1_NAME=faas-subnet-1
            OCI_FN_SUBNET_2_NAME=faas-subnet-2
            OCI_FN_SUBNET_3_NAME=faas-subnet-3
            VCN_PARAMS="--compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --query 'data.id' --raw-output"
            OCI_SUBNET_1=$(oci network subnet create --display-name ${OCI_FN_SUBNET_1_NAME} --cidr-block "${OCI_FN_VCN_SUBNET_1_CIDR_BLOCK}" ${VCN_PARAMS})
            OCI_SUBNET_2=$(oci network subnet create --display-name ${OCI_FN_SUBNET_2_NAME} --cidr-block "${OCI_FN_VCN_SUBNET_2_CIDR_BLOCK}" ${VCN_PARAMS})
            OCI_SUBNET_3=$(oci network subnet create --display-name ${OCI_FN_SUBNET_3_NAME} --cidr-block "${OCI_FN_VCN_SUBNET_3_CIDR_BLOCK}" ${VCN_PARAMS})
            echo Created subnets: ${OCI_FN_SUBNET_1_NAME}, ${OCI_FN_SUBNET_2_NAME}, ${OCI_FN_SUBNET_3_NAME}

          #The subnets specified should be public only if function needs internet access
            # and also have appropriate rules in its security list and route table
            # If single subnet, it is recommended that the subnet is regional/multi-AD
            # We do need internet access since we are accessing Kafka bootstrap servers over internet. TODO..is there service gatewaty for both OCI-OSS and OCI-OS?
            # create internet gateway:
            OCI_FN_INTERNET_GATEWAY_NAME=faas-internet-gateway
            OCI_FN_INTERNET_GATEWAY_ID=$(oci network internet-gateway create --display-name ${OCI_FN_INTERNET_GATEWAY_NAME} --is-enabled true ${VCN_PARAMS})
            echo Created internet gateway ${OCI_FN_INTERNET_GATEWAY_NAME} with ID ${OCI_FN_INTERNET_GATEWAY_ID}

          # update default route table: (rule allows all internet traffic to hit the internet gateway we just created)
            ROUTE_RULES="[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\""${OCI_FN_INTERNET_GATEWAY_ID}"\"}]"
            echo $ROUTE_RULES >route-rules.json
            oci network route-table update --rt-id ${OCI_FN_VCN_ROUTE_TABLE_ID} --route-rules file://$(pwd)/route-rules.json --force
            echo Updated default route table for VCN to allow traffic to internet gateway
            rm route-rules.json

          # update default security list
            curl -O https://raw.githubusercontent.com/mayur-oci/OssFunctions/master/AutomationScripts/ingress.json
            curl -O https://raw.githubusercontent.com/mayur-oci/OssFunctions/master/AutomationScripts/egress.json
            oci network security-list update --security-list-id ${OCI_FN_VCN_SECURITY_LIST_ID} \
                                    --ingress-security-rules file://`pwd`/ingress.json  \
                                    --egress-security-rules file://`pwd`/egress.json --force
            echo Updated default security list for all subnets in VCN
            rm ingress.json
            rm egress.json

          printf "\nYour new compartment ID is "${OCI_CMPT_ID}"\n"
          printf "Your subnet IDs are:\n\n"${OCI_FN_SUBNET_1_NAME}": "${OCI_SUBNET_1}"\n"${OCI_FN_SUBNET_2_NAME}": "${OCI_SUBNET_2}"\n"${OCI_FN_SUBNET_3_NAME}":"${OCI_SUBNET_3}"\n"
          printf "\nUse these subnets for your Fn applications."
          printf "tenancy="${OCI_TENANCY_NAME}"\n"
          printf "region="${OCI_CURRENT_REGION}"\n"

          printf "\nOCI Fn Config Complete.  Your tenancy is now set up to use Fn."

#Create user and its group. We will use this user( and its auth token) for authentication in following 3 scenarios.
          # 1- to enable Kafka Producer functions to write to OSS stream, using Kafka Compatible API. User credentials will be passed to function as configs values
          # 2- kafka-fn-sink worker will use the same user credentials for reading from OSS stream
          # 3- logging into OCI container registry used for docker images of functions
          #Needless to say this user is different than the user executing this script. We could have used credentials of this user too.
          OCI_FN_USER_NAME=faas_user
          OCI_FN_GROUP_NAME=faas_user_group
          # create group
          OCI_FN_GROUP_ID=$(oci iam group create --name ${OCI_FN_GROUP_NAME} --description "A group for FaaS users" --region ${OCI_HOME_REGION} --query "data.id" --raw-output)
          echo Created group ${OCI_FN_GROUP_NAME} with ID ${OCI_FN_GROUP_ID}

          # create user:
          OCI_FN_USER_ID=$(oci iam user create --name ${OCI_FN_USER_NAME} --description "A user for the FaaS service" --region ${OCI_HOME_REGION} --query "data.id" --raw-output)
          echo Created user ${OCI_FN_USER_NAME} with ID ${OCI_FN_USER_ID}

          # create user auth token
          OCI_FN_USER_AUTH_TOKEN=$(oci iam auth-token create --user-id ${OCI_FN_USER_ID} --description "auth token for ${OCI_FN_USER_NAME}" --region ${OCI_HOME_REGION} --query "data.token" --raw-output)
          echo Created Auth Token.  Remember this token, it can not be retrieved in the future: "${OCI_FN_USER_AUTH_TOKEN}"

          # add user to group:
          oci iam group add-user --group-id ${OCI_FN_GROUP_ID} --user-id ${OCI_FN_USER_ID} --region ${OCI_HOME_REGION} --raw-output --query "data.id"
          echo Added user ${OCI_FN_USER_NAME} to group ${OCI_FN_GROUP_NAME}

          # Create group policy.
          # TODO remove all rights to group ... give access to object storage and streams read, write
          STATEMENTS="[\"Allow group "${OCI_FN_GROUP_NAME}" to manage all-resources in compartment $OCI_CMPT_NAME \" ,\"Allow group "${OCI_FN_GROUP_NAME}" to manage repos in tenancy\", \"Allow group "${OCI_FN_GROUP_NAME}" to manage functions-family in compartment "${OCI_CMPT_NAME}"\", \"Allow group "${OCI_FN_GROUP_NAME}" to manage vnics in compartment "${OCI_CMPT_NAME}"\", \"Allow group "${OCI_FN_GROUP_NAME}" to inspect subnets in compartment "${OCI_CMPT_NAME}"\"]"
          echo $STATEMENTS > statements.json
          OCI_FN_POLICY_ID=$(oci iam policy create --name Policy_for_$OCI_FN_GROUP_NAME --description "A policy for the group ${OCI_FN_GROUP_NAME}" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE --wait-interval-seconds 3)
          echo Created policy Policy_for_$OCI_FN_GROUP_NAME.  Use the command: \'oci iam policy get --policy-id "${OCI_FN_POLICY_ID}"\' if you want to view the policy.

#Create Function App(a logical container for functions). Inside this app, we will create producer and consumer function
#Consumer function will be triggered by Kafka FnSink connector
          #Fn Context setup
            FN_CONTEXT=fn_oss_cntx
            fn delete context $FN_CONTEXT # just to make script idempotent
            fn create context $FN_CONTEXT --provider oracle 
            fn use context $FN_CONTEXT
            fn update context oracle.compartment-id $OCI_CMPT_ID
            fn update context api-url "https://functions.${OCI_CURRENT_REGION}.oraclecloud.com" # this is the OCI fn service url, again this is region specific
            fn update context oracle.profile $OCI_CLI_PROFILE # make sure to update your local ~./oci/config file with api and other credentials for this user
          
            #Docker setup for fn platform
            OCI_DOCKER_REGISTRY_URL="https://${OCI_CURRENT_REGION_CODE}.ocir.io"  # OCI docker registry URL. It is region specific e.g. for Ashburn iad.ocir.io
            FN_DOCKER_REPO_NAME=docker_repo_fn_oss_test # Your docker repo name...will be created when we push fn docker image
            FN_DOCKER_REPO_URL=$OCI_DOCKER_REGISTRY_URL/$OCI_TENANCY_NAME/$FN_DOCKER_REPO_NAME
            fn update context registry $FN_DOCKER_REPO_URL
            
          #Optional...if fn setup is done correctely this command should run without any issues.
            fn list apps 

          #You need to login, to allow you to push the function docker image to registry, when you build and deploy the function code
            docker login -u $OCI_TENANCY_NAME/$OCI_USER_ID -p $OCI_FN_USER_AUTH_TOKEN $OCI_DOCKER_REGISTRY_URL

          #Create application for the function. This app is just logical container for both consumer and producer functions for our stream of product reviews
            FN_APP_NAME=fn_oss_app_test
            OCI_SUBNETID_LIST_JSON=[\"$OCI_SUBNET_1\", \"$OCI_SUBNET_2\", \"$OCI_SUBNET_3\"]
            fn create app $FN_APP_NAME  --annotation oracle.com/oci/subnetIds=$OCI_SUBNETID_LIST_JSON
            TAIL_URL=tcp://logs5.papertrailapp.com:45170 #optional
            if [ ! -z "$TAIL_URL" ]; then
               fn update app $FN_APP_NAME --syslog-url $TAIL_URL
            fi   

          #Configs for the functions
            #Configs for Kafka Producer function    
            fn config app $FN_APP_NAME OCI_TENANCY_NAME $OCI_TENANCY_NAME
            fn config app $FN_APP_NAME OCI_OSS_KAFKA_BOOTSTRAP_SERVERS "streaming.${OCI_CURRENT_REGION}.oci.oraclecloud.com:9092" # again depends on OCI region where your stream is.
            fn config app $FN_APP_NAME STREAM_POOL_NAME $OCI_STREAM_POOL_NAME
            fn config app $FN_APP_NAME REVIEWS_STREAM_OR_TOPIC_NAME $OCI_STREAM_NAME
            fn config app $FN_APP_NAME STREAM_POOL_OCID $OCI_STREAM_POOL_ID
            fn config app $FN_APP_NAME OCI_USER_ID $OCI_USER_ID
            #TODO use OCI secrets instead of config for auth token
            fn config app $FN_APP_NAME OCI_AUTH_TOKEN $OCI_FN_USER_AUTH_TOKEN 

            #Configs for Kafka Consumer function
            fn config app $FN_APP_NAME OCI_OBJECT_STORAGE_NAMESPACE $OCI_TENANCY_NAME
            fn config app $FN_APP_NAME OCI_OBJECT_STORAGE_REGION $OCI_CURRENT_REGION
            fn config app $FN_APP_NAME GOOD_REVIEW_BUCKET_NAME $GOOD_REVIEW_BUCKET_NAME 
            fn config app $FN_APP_NAME BAD_REVIEWS_BUCKET_NAME $BAD_REVIEWS_BUCKET_NAME
            fn config app $FN_APP_NAME UNPUBLISHBALE_WORD_LIST 'bad1,bad2,bad3,bad4'

          #Fetch the function code from github and actually deploy it in OCI Fn platform
            FN_REPO_NAME=OssFunctions
            FN_GITHUB_URL="https://github.com/mayur-oci/${FN_REPO_NAME}.git"
            git clone $FN_GITHUB_URL
             
            fn -v deploy --app $FN_APP_NAME --no-bump ./$FN_REPO_NAME/ReviewConsumerFn
            fn update function $FN_APP_NAME review_consumer_fn --memory 512 --timeout 120
            
            fn -v deploy --app $FN_APP_NAME --no-bump ./$FN_REPO_NAME/ReviewProducerFn
            fn update function $FN_APP_NAME review_producer_fn --memory 512 --timeout 120 

#Create Compute Instance for running Kafka Oci Fn Sink Connector
        AD=$(oci iam availability-domain list --region ${OCI_CURRENT_REGION} --query "(data[?ends_with(name, '-3')] | [0].name) || data[0].name" --raw-output)
        echo availability-domain chosen for compute instance: $AVAILABILITY_DOMAIN
        
        COMPUTE_SHAPE='VM.Standard1.4'
        SSH_PUBLIC_KEY_LOCATION="/Users/mraleras/sshkeypair1.key.pub" # Use your ssh public key file location here
        #Image ocid depends on region. Get image ocid from https://docs.cloud.oracle.com/en-us/iaas/images/image/96068886-76e5-4a48-af0a-fa7ed8466a25/
        ORALCE_LINUX_IMAGE_OCID='ocid1.image.oc1.phx.aaaaaaaaym3vkgeag7mn3csoxxvk6gdirryocsubuv2xvgefhi2wrwytp2gq'
        COMPUTE_OCID=$(oci compute instance launch \
                            -c ${OCI_CMPT_ID} \
                            --shape "${COMPUTE_SHAPE}" \
                            --display-name FnSinkConnectorVM \
                            --image-id ${ORALCE_LINUX_IMAGE_OCID} \
                            --ssh-authorized-keys-file "${SSH_PUBLIC_KEY_LOCATION}" \
                            --subnet-id ${OCI_SUBNET_1} \
                            --availability-domain "${AD}" \
                            --wait-for-state RUNNING \
                            --query "data.id" \
                            --raw-output) 
        #Get the Public IP
        COMPUTE_PUBLIC_IP=$(oci compute instance list-vnics \
            --instance-id "${COMPUTE_OCID}" \
            --query 'data[0]."public-ip"' \
            --raw-output)
            echo 'The OCI Oracle Linux Compute Instance IP is' $COMPUTE_IP     
        #Create Dynamic group and policy for your above instance to call consumer function review_consumer_fn
        MATCHING_RULE_FOR_DG="ANY {instance.id = '${COMPUTE_OCID}'}"
        DG_NAME='dg_for_kafka_fn_sink'_$(date "+DATE_%Y_%m_%d_TIME_%H_%M_%S")
        DG_ID=$(oci --region $OCI_HOME_REGION iam dynamic-group create --description 'dg_for_kafka_fn_sink' --name 'dg_for_kafka_fn_sink' --matching-rule "$MATCHING_RULE_FOR_DG" --wait-for-state ACTIVE --query "data.id" --raw-output)

        DG_POLICY="[\"Allow dynamic-group dg_for_kafka_fn_sink to use log-content in compartment ${OCI_CMPT_NAME} \"]"
        echo $DG_POLICY > statements.json
        DG_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "DG_POLICY_$DG_NAME" --description "A policy for instance" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE)
        echo Created policy ${DG_POLICY_ID}.  Use the command: \'oci iam policy get --policy-id "${DG_POLICY_ID}"\' if you want to view the policy.
        rm -rf statements.json                        

        # transfer env values for docker

        echo CONNECT_HARNESS_OCID=${OCI_CONNECT_HARNESS_ID} > env.json
        echo OCID_STREAM_POOL=${OCI_STREAM_POOL_ID} > env.json
        echo OCI_USER_ID=${OCI_USER_ID} > env.json
        echo OCI_USER_AUTH_TOKEN=${OCI_FN_USER_AUTH_TOKEN} > env.json
        echo OCI_STREAM_PARTITIONS_COUNT=${OCI_STREAM_PARTITIONS_COUNT} > env.json


        # SSH into the node, set it up JDK 8, maven, docker, configure firewall and start the Fn Sink Connector
        export GIT_SETUP_EXPORTER="https://raw.githubusercontent.com/mayur-oci/OssFunctions/master/AutomationScripts/SetupOciInstanceForFnSinkConnector.sh"
        SSH_PRIVATE_KEY_LOCATION="/Users/mraleras/sshkeypair1.key.pvt" 
        ssh -i $SSH_PRIVATE_KEY_LOCATION opc@$COMPUTE_PUBLIC_IP -o ServerAliveInterval=60 -o "StrictHostKeyChecking no" \
                "curl -O $GIT_SETUP_EXPORTER; chmod 777 SetupOciInstanceForLogExporter.sh"
        echo;echo;echo "Run the Script for setup after with root privileges aka 'sudo ./SetupOciInstanceForLogExporter.sh' on the instance"

        ssh -i $SSH_PRIVATE_KEY_LOCATION opc@$COMPUTE_PUBLIC_IP -o ServerAliveInterval=60 -o "StrictHostKeyChecking no"



#Start Kafka Fn Sink Connector worker 
        FN_CONSUMER_FUNCTION_NAME=fn_oss_app_test
        OCI_STREAM_PARTITIONS_COUNT=1
        FN_CONSUMER_FUNCTION_NAME=review_consumer_fn
        FN_CONNECTOR_NAME="FnSinkConnector_2"

        curl -X DELETE http://${COMPUTE_PUBLIC_IP}:8082/connectors/$FN_CONNECTOR_NAME

        echo "Connector $FN_CONNECTOR_NAME deleted"

        curl -X POST \
          http://${COMPUTE_PUBLIC_IP}:8082/connectors \
          -H 'content-type: application/json' \
          -d "{
          \"name\": \"${FN_CONNECTOR_NAME}\",
          \"config\": {
            \"connector.class\": \"io.fnproject.kafkaconnect.sink.FnSinkConnector\",
            \"tasks.max\": \"${OCI_STREAM_PARTITIONS_COUNT}\",
            \"topics\": \"${OCI_STREAM_NAME}\",
            \"ociRegionForFunction\": \"${OCI_CURRENT_REGION}\",
            \"ociCompartmentIdForFunction\": \"${OCI_CMPT_ID}\",
            \"functionAppName\": \"${FN_APP_NAME}\",
            \"functionName\": \"${FN_CONSUMER_FUNCTION_NAME}\",
            \"ociLocalConfig\": \"${HOME}\"
          }
        }"

#Invoke Producer Function
        echo -n '{"reviewId": "REV_100", "time": 200010000000000, "productId": "PRODUCT_100", "reviewContent": "review content"}' \
        | fn invoke $FN_APP_NAME review_producer_fn
        echo -n '{"reviewId": "REV_200", "time": 200010000000000, "productId": "PRODUCT_200", "reviewContent": "review content bad2"}' \
        | fn invoke $FN_APP_NAME review_producer_fn


exit


# for local fn testing
OCI_OBJECT_STORAGE_NAMESPACE=intrandallbarnes
GOOD_REVIEW_BUCKET_NAME=goodRevBucket
BAD_REVIEWS_BUCKET_NAME=badRevBucket
OCI_OBJECT_STORAGE_REGION=us-phoenix-1
OCI_OSS_KAFKA_BOOTSTRAP_SERVERS=streaming.us-phoenix-1.oci.oraclecloud.com:9092
OCI_TENANCY_NAME=intrandallbarnes
OCI_USER_ID=mayur.raleraskar@oracle.com
OCI_AUTH_TOKEN=2m{s4WTCXysp:o]tGx4K
STREAM_POOL_OCID=ocid1.streampool.oc1.phx.amaaaaaauwpiejqactzuddgmegg42gkhwpz24wy6k7ka3n24nc52mpzqfvua
REVIEWS_STREAM_OR_TOPIC_NAME=testnew
UNPUBLISHBALE_WORD_LIST="bad1,bad2,bad3,bad4"





