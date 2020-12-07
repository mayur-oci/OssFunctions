
#Basic tenancy and user information. User needs admin privileges.
          OCI_TENANCY_NAME=intrandallbarnes
          OCI_TENANCY_OCID=ocid1.tenancy.oc1..aaaaaaaaopbu45aomik7sswe4nzzll3f6ii6pipd5ttw4ayoozez37qqmh3a

          OCI_HOME_REGION=us-ashburn-1
          OCI_CURRENT_REGION=us-phoenix-1 # from OCI config file
          OCI_CMPT_NAME=CMPT_FOR_OSS_FN_INTEGRATION_D
          OCI_CLI_PROFILE=DEFAULT

#Create new compartment for this demo...We will create all resources for this demo inside this compartment.
          OCI_CMPT_ID=$(oci iam compartment create --name ${OCI_CMPT_NAME} --compartment-id ocid1.tenancy.oc1..aaaaaaaaopbu45aomik7sswe4nzzll3f6ii6pipd5ttw4ayoozez37qqmh3a --description "A compartment to fn oss integration" --region ${OCI_HOME_REGION} --query "data.id" --raw-output)
          echo Created compartment ${OCI_CMPT_NAME} with ID ${OCI_CMPT_ID}


#Create Dynamic group and policy for your function
          MATCHING_RULE_FOR_FN_DG="ALL {resource.type = 'fnfunc', resource.compartment.id=$OCI_CMPT_ID}	"
          OCI_FN_DG_ID=$(oci --region $OCI_HOME_REGION iam dynamic-group create --description 'for_fns_in_cmpt' --name "fn_dg_$OCI_CMPT_NAME" --matching-rule "$MATCHING_RULE_FOR_FN_DG" --wait-for-state ACTIVE --query "data.id" --raw-output)

          FN_POLICY="[\"Allow dynamic-group "fn_dg_$OCI_CMPT_NAME" to manage all-resources in compartment $OCI_CMPT_NAME \"]"
          echo $FN_POLICY > statements.json
          OCI_FN_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "DG_POLICY_$OCI_CMPT_NAME" --description "A policy for these functions" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE)
          echo Created policy ${OCI_FN_POLICY_NAME}.  Use the command: \'oci iam policy get --policy-id "${OCI_FN_POLICY_ID}"\' if you want to view the policy.
          rm -rf statements.json

#Create Policy for allowing FaaS service(hence your function) to access
          # 1- docker repo for getting function code and
          # 2- subnets for running funnctions inside it. We will soon create functions
          FN_POLICY="[\"Allow service FaaS to read repos in tenancy\", \"Allow service FaaS to use virtual-network-family in compartment $OCI_CMPT_NAME\"]"
          echo $FN_POLICY > statements.json
          OCI_FN_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "FaaS_POLICY_$OCI_CMPT_NAME" --description "A policy for FaaS functions" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE)
          echo Created policy "FaaS_POLICY_$OCI_CMPT_NAME".  Use the command: \'oci iam policy get --policy-id "${OCI_FN_POLICY_ID}"\' if you want to view the policy.
          rm -rf statements.json

# TODO create DG and DG policy for fn sink worker node. Create node and deploy worker code on it!

# Creating subnets for OCI functions and KafkaFnSink worker node
          OCI_FN_POLICY_NAME=faas-demo-policy
          OCI_FN_VCN_NAME=faas-demo-vcn
          OCI_FN_VCN_CIDR_BLOCK=10.0.0.0/16
          OCI_FN_SUBNET_1_NAME=faas-subnet-1
          OCI_FN_SUBNET_2_NAME=faas-subnet-2
          OCI_FN_SUBNET_3_NAME=faas-subnet-3

          echo $(oci iam availability-domain list --all --query 'data[?contains(name, `'"${availability_domain}"'`)] | [0].name' --raw-output)
          OCI_FN_SUBNET_1_AD=pqpf:PHX-AD-1
          OCI_FN_SUBNET_2_AD=pqpf:PHX-AD-1
          OCI_FN_SUBNET_3_AD=pqpf:PHX-AD-1
          OCI_FN_VCN_SUBNET_1_CIDR_BLOCK=10.0.1.0/24
          OCI_FN_VCN_SUBNET_2_CIDR_BLOCK=10.0.2.0/24
          OCI_FN_VCN_SUBNET_3_CIDR_BLOCK=10.0.3.0/24
          OCI_FN_INTERNET_GATEWAY_NAME=faas-internet-gateway

          # create VCN:
          echo Creating VCN. This may take a few seconds...
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
          OCI_SUBNET_1=$(oci network subnet create --display-name ${OCI_FN_SUBNET_1_NAME} --availability-domain ${OCI_FN_SUBNET_1_AD} --cidr-block "${OCI_FN_VCN_SUBNET_1_CIDR_BLOCK}" --compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --query 'data.id' --raw-output)
          OCI_SUBNET_2=$(oci network subnet create --display-name ${OCI_FN_SUBNET_2_NAME} --availability-domain ${OCI_FN_SUBNET_2_AD} --cidr-block "${OCI_FN_VCN_SUBNET_2_CIDR_BLOCK}" --compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --query 'data.id' --raw-output)
          OCI_SUBNET_3=$(oci network subnet create --display-name ${OCI_FN_SUBNET_3_NAME} --availability-domain ${OCI_FN_SUBNET_3_AD} --cidr-block "${OCI_FN_VCN_SUBNET_3_CIDR_BLOCK}" --compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --query 'data.id' --raw-output)
          echo Created subnets: ${OCI_FN_SUBNET_1_NAME}, ${OCI_FN_SUBNET_2_NAME}, ${OCI_FN_SUBNET_3_NAME}

          # The subnets specified should be public only if function needs internet access
          # and also have appropriate rules in its security list and route table
          # If single subnet, it is recommended that the subnet is multi-AD, for HA.
          # We do need internet access since we are accessing Kafka bootstrap servers over internet TODO..is there service gatewaty?
          # create internet gateway:
          OCI_FN_INTERNET_GATEWAY_ID=$(oci network internet-gateway create --display-name ${OCI_FN_INTERNET_GATEWAY_NAME} --is-enabled true --compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --query 'data.id' --raw-output)
          echo Created internet gateway ${OCI_FN_INTERNET_GATEWAY_NAME} with ID ${OCI_FN_INTERNET_GATEWAY_ID}

          # update default route table: (rule allows all internet traffic to hit the internet gateway we just created)
          ROUTE_RULES="[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\""${OCI_FN_INTERNET_GATEWAY_ID}"\"}]"
          echo $ROUTE_RULES >route-rules.json
          OCI_ROUTE_TABLE_UPDATE=$(oci network route-table update --rt-id ${OCI_FN_VCN_ROUTE_TABLE_ID} --route-rules file://$(pwd)/route-rules.json --force)
          echo Updated default route table for VCN to allow traffic to internet gateway

          # update default security list

          OCI_SECURITY_LIST_UPDATE=$(oci network security-list update --security-list-id ${OCI_FN_VCN_SECURITY_LIST_ID} --ingress-security-rules '[{"source": "0.0.0.0/0", "protocol": "6", "isStateless": false, "tcpOptions": {"destinationPortRange": {"max": 80, "min": 80}, "sourcePortRange": {"max": 80, "min": 80}}}]' --force)
          echo Updated default security list to open port 80 for all subnets in VCN

          printf "\nYour new compartment ID is "${OCI_CMPT_ID}"\n"
          printf "Your subnet IDs are:\n\n"${OCI_FN_SUBNET_1_NAME}": "${OCI_SUBNET_1}"\n"${OCI_FN_SUBNET_2_NAME}": "${OCI_SUBNET_2}"\n"${OCI_FN_SUBNET_3_NAME}":"${OCI_SUBNET_3}"\n"
          printf "\nUse these subnets for your Fn applications."
          printf "tenancy="${OCI_TENANCY_NAME}"\n"
          printf "region="${OCI_CURRENT_REGION}"\n"

          printf "\nOCI Fn Config Complete.  Your tenancy is now set up to use Fn."
          rm statements.json >/dev/null 2>&1
          rm route-rules.json >/dev/null 2>&1

#Create OCI streampool and stream(aka Kafka Topic) in it
          OCI_STREAM_POOL_NAME=REVIEWS_STREAM_POOL
          OCI_STREAM_NAME=REVIEWS_STREAM
          OCI_STREAM_PARTITIONS_COUNT=3
          OCI_STREAM_POOL_ID=$(oci streaming admin stream-pool create -c ${OCI_CMPT_ID} --name ${OCI_STREAM_POOL_NAME} --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_STREAM_ID=$(oci streaming admin stream create --name ${OCI_STREAM_NAME} --partitions ${OCI_STREAM_PARTITIONS_COUNT} --stream-pool-id ${OCI_STREAM_POOL_ID} --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_CONNECT_HARNESS_ID=$(oci streaming admin connect-harness create --region ${OCI_CURRENT_REGION} -c ${OCI_CMPT_ID} --name ConnectHarnessForFnSink --wait-for-state ACTIVE --query "data.id" --raw-output)

#Create buckets for processed reviews
          GOOD_REVIEW_BUCKET_NAME=GoodReviewsBucket
          BAD_REVIEWS_BUCKET_NAME=BadReviewsBucket
          GOOD_REVIEWS_BUCKET_OCID=$(oci os bucket create --name ${GOOD_REVIEW_BUCKET_NAME} -c $OCI_CMPT_ID --region $OCI_CURRENT_REGION --raw-output --query "data.id")
          BAD_REVIEWS_BUCKET_OCID=$(oci os bucket create --name ${BAD_REVIEWS_BUCKET_NAME} -c $OCI_CMPT_ID --region $OCI_CURRENT_REGION --raw-output --query "data.id")

#Create user and its group. We will use this user( and its auth token) for authentication in following 3 scenarios.
    # 1- to enable Kafka Producer functions to write to OSS stream, using Kafka Compatible API. User credentials will be passed to function as configs values
    # 2- kafka-fn-sink worker will use the same user credentials for reading from OSS stream
    # 3- logging into OCI container registry used for docker images of functions
          #Needless to say this user is different than the user executing this script. We could have used credentials of this user too.
          OCI_FN_USER_NAME=faas_user
          OCI_FN_GROUP_NAME=faas_group
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
          OCI_FN_POLICY_ID=$(oci iam policy create --name ${OCI_FN_POLICY_NAME} --description "A policy for the group ${OCI_FN_GROUP_NAME}" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE --wait-interval-seconds 3)
          echo Created policy ${OCI_FN_POLICY_NAME}.  Use the command: \'oci iam policy get --policy-id "${OCI_FN_POLICY_ID}"\' if you want to view the policy.

#Create FunctionApp(a logical container for functions). Inside this app, we will create producer and consumer function
#Consumer function will be triggered by Kafka FnSink connector
          OCI_CMPT_OCID=$OCI_CMPT_ID # OCID of OCI compartment where you want your function to reside
          OCI_USER_ID=$OCI_FN_GROUP_ID
          OCI_AUTH_TOKEN=$OCI_FN_USER_AUTH_TOKEN
          OCI_DOCKER_REGISTRY_URL="https://phx.ocir.io"  # OCI docker registry URL. It is region specific e.g. for Ashburn iad.ocir.io
          OCI_TENANCY_NAME=$OCI_TENANCY_NAME

          FN_CONTEXT=fn_oss_cntx
          FN_OCI_PLATFORM_URL='https://functions.us-phoenix-1.oraclecloud.com' # this is the OCI fn service url, again this is region specific
          FN_DOCKER_REPO_NAME=docker_repo_fn_oss_test # Your docker repo name...will be created when we push fn docker image
          FN_DOCKER_REPO_URL=$OCI_DOCKER_REGISTRY_URL/$OCI_TENANCY_NAME/$FN_DOCKER_REPO_NAME
          FN_APP_NAME=fn_oss_app_test # Name for the application for the function. Application is a logical container for functions in Oracle Cloud Function platform.
          FN_PRODUCER_FUNCTION_NAME=ReviewProducerFn
          FN_CONSUMER_FUNCTION_NAME=ReviewConsumerFn
          FN_GITHUB_REPO_NAME=oci_fn_jira_integration
          FN_GITHUB_URL="https://github.com/mayur-oci/$FN_GITHUB_REPO_NAME.git"


          fn create context $FN_CONTEXT
          fn use context $FN_CONTEXT
          fn update context oracle.compartment-id $OCI_CMPT_OCID
          fn update context api-url $FN_OCI_PLATFORM_URL
          fn update context registry $FN_DOCKER_REPO_URL
          fn update context oracle.profile $OCI_CLI_PROFILE # make sure to update your local ~./oci/config file with api and other credentials for this user

          # You need to login, to allow you to push the function docker image to registry, when you build and deploy the function code
          docker login -u $OCI_TENANCY_NAME/$OCI_USER_ID -p $OCI_AUTH_TOKEN $OCI_DOCKER_REGISTRY_URL

          # Create application for the function
          OCI_SUBNETID_LIST_JSON=[\"$OCI_SUBNET_1\", \"$OCI_SUBNET_2\", \"$OCI_SUBNET_3\"]
          # this app is just logical container for both consumer and producer functions for our stream of product reviews
          fn create app $FN_APP_NAME  --annotation oracle.com/oci/subnetIds=$OCI_SUBNETID_LIST_JSON
          sleep 5

          fn config app $FN_APP_NAME OCI_TENANCY_NAME $OCI_TENANCY_NAME
          fn config app $FN_APP_NAME OCI_CMPT_OCID $OCI_CMPT_OCID
          fn config app $FN_APP_NAME OCI_CMPT_NAME $OCI_CMPT_NAME
          fn config app $FN_APP_NAME OCI_USER_ID $OCI_USER_ID
          fn config app $FN_APP_NAME OCI_OBJECT_STORAGE_REGION $OCI_CURRENT_REGION

          fn config app $FN_APP_NAME OCI_OSS_KAFKA_BOOTSTRAP_SERVERS "streaming.us-phoenix-1.oci.oraclecloud.com:9092" # again depends on OCI region where your stream is.
          fn config app $FN_APP_NAME STREAM_POOL_NAME $OCI_STREAM_POOL_NAME
          fn config app $FN_APP_NAME REVIEWS_STREAM_NAME $OCI_STREAM_NAME
          fn config app $FN_APP_NAME STREAM_POOL_OCID $OCI_STREAM_POOL_ID
          fn config app $FN_APP_NAME REVIEWS_STREAM_OCID $OCI_STREAM_ID

          fn config app $FN_APP_NAME OCI_OBJECT_STORAGE_NAMESPACE $OCI_TENANCY_NAME
          fn config app $FN_APP_NAME GOOD_REVIEW_BUCKET_NAME $GOOD_REVIEW_BUCKET_NAME
          fn config app $FN_APP_NAME BAD_REVIEWS_BUCKET_NAME $BAD_REVIEWS_BUCKET_NAME
          fn config app $FN_APP_NAME GOOD_REVIEWS_BUCKET_OCID $GOOD_REVIEWS_BUCKET_OCID
          fn config app $FN_APP_NAME BAD_REVIEWS_BUCKET_OCID $BAD_REVIEWS_BUCKET_OCID

          OCI_STREAM_POOL_NAME=REVIEWS_STREAM_POOL
          OCI_STREAM_NAME=REVIEWS_STREAM
          OCI_STREAM_PARTITIONS_COUNT=3
          OCI_STREAM_POOL_ID=$(oci streaming admin stream-pool create -c ${OCI_CMPT_ID} --name ${OCI_STREAM_POOL_NAME} --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_STREAM_ID=

          fn init --runtime java hello-java
          cd hello-java
          fn -v deploy --app $FN_APP_NAME

# for local fn testing
OCI_OBJECT_STORAGE_NAMESPACE=intrandallbarnes
GOOD_REVIEW_BUCKET_NAME=goodRevBucket
BAD_REVIEWS_BUCKET_NAME=badRevBucket
OCI_CURRENT_REGION=us-phoenix-1
OCI_OSS_KAFKA_BOOTSTRAP_SERVERS=streaming.us-phoenix-1.oci.oraclecloud.com:9092
OCI_TENANCY_NAME=intrandallbarnes
OCI_USER_ID=mayur.raleraskar@oracle.com
OCI_AUTH_TOKEN=2m{s4WTCXysp:o]tGx4K
STREAM_POOL_OCID=ocid1.streampool.oc1.phx.amaaaaaauwpiejqactzuddgmegg42gkhwpz24wy6k7ka3n24nc52mpzqfvua
REVIEWS_STREAM=testnew
UNPUBLISHBALE_WORD_LIST="bad1,bad2,bad3,bad4"





