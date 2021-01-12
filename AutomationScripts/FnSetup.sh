# #!/bin/bash

#Pre-reqs oci cli, fn cli needs to installed the machine

#Basic tenancy and user information. User needs admin privileges.
          OCI_TENANCY_NAME=intrandallbarnes
          OCI_TENANCY_OCID=ocid1.tenancy.oc1..aaaaaaaaopbu45aomik7sswe4nzzll3f6ii6pipd5ttw4ayoozez37qqmh3a

          OCI_HOME_REGION=us-ashburn-1
          OCI_CURRENT_REGION=us-phoenix-1 # from OCI config file
          OCI_CLI_PROFILE=DEFAULT
          OCI_CURRENT_REGION_CODE=phx
        

#Common utility functions          
          JobRunId=$(date "+DATE_%Y_%m_%d_TIME_%H_%M")      
          mkdir $JobRunId
          cd $JobRunId    
          ocidList=resourceIdList_For_JobRun_${JobRunId}.sh
          out(){
            echo $1 | tee -a ${ocidList}
          }
          out "JobRunId=${JobRunId}"


#Create new compartment for this demo...We will create all resources for this demo inside this compartment.
          OCI_CMPT_NAME=OssFn_${JobRunId}
          OCI_CMPT_ID=$(oci iam compartment create --name ${OCI_CMPT_NAME} --compartment-id ${OCI_TENANCY_OCID} \
                         --description "A compartment to fn oss integration" --region ${OCI_HOME_REGION} --wait-for-state ACTIVE --query "data.id" --raw-output)
          out "OCI_CMPT_NAME=${OCI_CMPT_NAME}" 
          out "OCI_CMPT_ID=${OCI_CMPT_ID}"
          out "OCI_TENANCY_OCID=${OCI_TENANCY_OCID}"

          echo Sleeping for some seconds, we need sleep since sometimes '--wait-for-state ACTIVE' for create compartment command does not work as expected.
          sleep 80
          
             
#Create OCI streampool and stream(aka Kafka Topic) in it
          OCI_STREAM_POOL_NAME=REVIEWS_STREAM_POOL
          OCI_STREAM_NAME=REVIEWS_STREAM
          OCI_STREAM_PARTITIONS_COUNT=1
          OCI_STREAM_POOL_ID=$(oci streaming admin stream-pool create -c ${OCI_CMPT_ID} --name ${OCI_STREAM_POOL_NAME} --region ${OCI_CURRENT_REGION} \
                              --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_STREAM_ID=$(oci streaming admin stream create --name ${OCI_STREAM_NAME} --partitions ${OCI_STREAM_PARTITIONS_COUNT} \
                         --region $OCI_CURRENT_REGION  --stream-pool-id ${OCI_STREAM_POOL_ID} --wait-for-state ACTIVE --query "data.id" --raw-output)
          OCI_CONNECT_HARNESS_ID=$(oci streaming admin connect-harness create --region ${OCI_CURRENT_REGION} -c ${OCI_CMPT_ID} \
                          --name ConnectHarnessForFnSink --wait-for-state ACTIVE --query "data.id" --raw-output)


          out "OCI_STREAM_POOL_ID=${OCI_STREAM_POOL_ID}"
          out "OCI_STREAM_ID=${OCI_STREAM_ID}"
          out "OCI_CONNECT_HARNESS_ID=${OCI_CONNECT_HARNESS_ID}"



#Create buckets for processed reviews
          GOOD_REVIEWS_BUCKET_NAME=goodRevBucket_${JobRunId}
          BAD_REVIEWS_BUCKET_NAME=badRevBucket_${JobRunId}
          GOOD_REVIEWS_BUCKET_OCID=$(oci os bucket create --name ${GOOD_REVIEWS_BUCKET_NAME} -c $OCI_CMPT_ID --region $OCI_CURRENT_REGION --raw-output --query "data.id")
          BAD_REVIEWS_BUCKET_OCID=$(oci os bucket create --name ${BAD_REVIEWS_BUCKET_NAME} -c $OCI_CMPT_ID --region $OCI_CURRENT_REGION --raw-output --query "data.id")
          out "GOOD_REVIEWS_BUCKET_OCID=${GOOD_REVIEWS_BUCKET_OCID}"
          out "BAD_REVIEWS_BUCKET_OCID=${BAD_REVIEWS_BUCKET_OCID}"

#Create Dynamic group and policy for your function resources and for allowing FaaS service(hence your function) to access
          # 1- docker repo for getting function code and
          # 2- subnets for running funnctions inside it. We will soon create functions
          MATCHING_RULE_FOR_FN_DG="ALL {resource.type = 'fnfunc', resource.compartment.id=$OCI_CMPT_ID}	"
          OCI_FN_DG_ID=$(oci --region $OCI_HOME_REGION iam dynamic-group create --description 'for_fns_in_cmpt' \
                        --name "fn_dg_$OCI_CMPT_NAME" --matching-rule "$MATCHING_RULE_FOR_FN_DG" \
                        --wait-for-state ACTIVE --query "data.id" --raw-output)

          FN_POLICY="[\"Allow dynamic-group "fn_dg_$OCI_CMPT_NAME" to \
                               manage all-resources in compartment $OCI_CMPT_NAME \", \
                      \"Allow service FaaS to read repos in tenancy\", \
                      \"Allow service FaaS to use virtual-network-family in compartment $OCI_CMPT_NAME\"]"
          echo $FN_POLICY > statements.json
          OCI_FN_DG_AND_FAAS_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "fn_dg_faas_policy_$OCI_CMPT_NAME" \
                                       --description "A policy for these function resources and faas" \
                                       --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} \
                                       --raw-output --query "data.id" --wait-for-state ACTIVE)
          echo Created policy "fn_dg_policy_$OCI_CMPT_NAME".  Use the command: \'oci iam policy get \
                       --policy-id "${OCI_FN_DG_POLICY_ID}"\' if you want to view the policy.
          rm -rf statements.json
          out "OCI_FN_DG_ID=${OCI_FN_DG_ID}"          
          out "OCI_FN_DG_AND_FAAS_POLICY_ID=${OCI_FN_DG_AND_FAAS_POLICY_ID}"        
          

#Creating subnets for 1- OCI functions and 2- compute instance(for Kafka FnSink Connector worker)
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
              OCI_FN_VCN_ID=$(oci network vcn create --cidr-block ${OCI_FN_VCN_CIDR_BLOCK} --compartment-id ${OCI_CMPT_ID} \
                             --display-name ${OCI_FN_VCN_NAME} --region ${OCI_CURRENT_REGION} --wait-for-state AVAILABLE --wait-interval-seconds 5 \
                             --query "data.id" --raw-output) && break
              n=$(($n + 1))
              echo [create failed, trying again in 10 seconds...]
              sleep 15
            done

            if [ $n -eq 6 ]; then
              echo "Could not create VCN, exiting script!"
              return
            else
              OCI_FN_VCN_ROUTE_TABLE_ID=$(oci network vcn get --vcn-id ${OCI_FN_VCN_ID} --region ${OCI_CURRENT_REGION} --query 'data."default-route-table-id"' --raw-output)
              OCI_FN_VCN_SECURITY_LIST_ID=$(oci network vcn get --vcn-id ${OCI_FN_VCN_ID} --region ${OCI_CURRENT_REGION} --query 'data."default-security-list-id"' --raw-output)
              echo Created VCN ${OCI_FN_VCN_NAME} with ID ${OCI_FN_VCN_ID}
            fi

            out "OCI_FN_VCN_ID=${OCI_FN_VCN_ID}"          
            out "OCI_FN_VCN_ROUTE_TABLE_ID=${OCI_FN_VCN_ROUTE_TABLE_ID}"          
            out "OCI_FN_VCN_SECURITY_LIST_ID=${OCI_FN_VCN_SECURITY_LIST_ID}"          

          # create subnets:
            OCI_FN_SUBNET_1_NAME=faas-subnet-1
            OCI_FN_SUBNET_2_NAME=faas-subnet-2
            OCI_FN_SUBNET_3_NAME=faas-subnet-3
            VCN_PARAMS="--compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --region ${OCI_CURRENT_REGION} --wait-for-state AVAILABLE "
            OCI_SUBNET_1=$(oci network subnet create --display-name ${OCI_FN_SUBNET_1_NAME} --cidr-block "${OCI_FN_VCN_SUBNET_1_CIDR_BLOCK}" ${VCN_PARAMS} | jq -r '.data.id')
            out "OCI_SUBNET_1=${OCI_SUBNET_1}"          

            OCI_SUBNET_2=$(oci network subnet create --display-name ${OCI_FN_SUBNET_2_NAME} --cidr-block "${OCI_FN_VCN_SUBNET_2_CIDR_BLOCK}" ${VCN_PARAMS} | jq -r '.data.id')
            out "OCI_SUBNET_2=${OCI_SUBNET_2}"          
 
            OCI_SUBNET_3=$(oci network subnet create --display-name ${OCI_FN_SUBNET_3_NAME} --cidr-block "${OCI_FN_VCN_SUBNET_3_CIDR_BLOCK}" ${VCN_PARAMS} | jq -r '.data.id')
            out "OCI_SUBNET_3=${OCI_SUBNET_3}"          
          

          #The subnets specified should be public only if function needs internet access
            # and also have appropriate rules in its security list and route table
            # If single subnet, it is recommended that the subnet is regional/multi-AD
            # We do need internet access since we are accessing Kafka bootstrap servers over internet. TODO..is there service gatewaty for both OCI-OSS and OCI-OS?
            # create internet gateway:
            OCI_FN_INTERNET_GATEWAY_NAME=faas-internet-gateway
            OCI_FN_INTERNET_GATEWAY_ID=$(oci network internet-gateway create --display-name ${OCI_FN_INTERNET_GATEWAY_NAME} \
                                       --is-enabled true --compartment-id ${OCI_CMPT_ID} --vcn-id ${OCI_FN_VCN_ID} --region ${OCI_CURRENT_REGION} \
                                       --wait-for-state AVAILABLE  --query 'data.id' --raw-output)
            out "OCI_FN_INTERNET_GATEWAY_ID=${OCI_FN_INTERNET_GATEWAY_ID}"

          # update default route table: (rule allows all internet traffic to hit the internet gateway we just created)
            ROUTE_RULES="[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\""${OCI_FN_INTERNET_GATEWAY_ID}"\"}]"
            echo $ROUTE_RULES >route-rules.json
            oci network route-table update --rt-id ${OCI_FN_VCN_ROUTE_TABLE_ID} --region ${OCI_CURRENT_REGION}  --route-rules file://$(pwd)/route-rules.json --force
            echo Updated default route table for VCN to allow traffic to internet gateway
            rm route-rules.json

          # update default security list
            curl -O https://raw.githubusercontent.com/mayur-oci/OssFunctions/master/AutomationScripts/ingress.json
            curl -O https://raw.githubusercontent.com/mayur-oci/OssFunctions/master/AutomationScripts/egress.json
            oci network security-list update --security-list-id ${OCI_FN_VCN_SECURITY_LIST_ID} --region ${OCI_CURRENT_REGION} \
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
          OCI_FN_USERNAME=faas_user_${JobRunId}
          out "OCI_FN_USERNAME=${OCI_FN_USERNAME}"
          OCI_FN_USERGROUP_NAME=faas_user_group_${JobRunId}
          out "OCI_FN_USERGROUP_NAME=${OCI_FN_USERGROUP_NAME}"
          # create group
          OCI_FN_USERGROUP_ID=$(oci iam group create --name ${OCI_FN_USERGROUP_NAME} --region ${OCI_HOME_REGION} --description "A group for FaaS users" --query "data.id" --raw-output)
          echo Created group ${OCI_FN_USERGROUP_ID} with ID ${OCI_FN_USERGROUP_ID}

          # create user:
          OCI_FN_USER_ID=$(oci iam user create --name ${OCI_FN_USERNAME} --region ${OCI_HOME_REGION} --description "A user for the FaaS service" --wait-for-state ACTIVE --query "data.id" --raw-output)
          echo Created user ${OCI_FN_USERNAME} with ID ${OCI_FN_USER_ID}

          # create user auth token
          OCI_FN_USER_AUTH_TOKEN=$(oci iam auth-token create --user-id ${OCI_FN_USER_ID} --description "auth token for ${OCI_FN_USERNAME}" --region ${OCI_HOME_REGION} --query "data.token" --raw-output)
          echo Created Auth Token.  Remember this token, it can not be retrieved in the future: "${OCI_FN_USER_AUTH_TOKEN}"
     
          # add user to group:
          oci iam group add-user --group-id ${OCI_FN_USERGROUP_ID} --user-id ${OCI_FN_USER_ID} --region ${OCI_HOME_REGION} --raw-output --query "data.id"
          echo Added user ${OCI_FN_USERNAME} to group ${OCI_FN_USERGROUP_NAME}

          # Create group policy.
          # TODO remove all rights to group ... give access to object storage and streams read, write
          STATEMENTS="[\"Allow group "${OCI_FN_USERGROUP_NAME}" to manage all-resources in compartment $OCI_CMPT_NAME \" ,\
                       \"Allow group "${OCI_FN_USERGROUP_NAME}" to manage repos in tenancy\", \
                       \"Allow group "${OCI_FN_USERGROUP_NAME}" to manage functions-family in compartment "${OCI_CMPT_NAME}"\", \
                       \"Allow group "${OCI_FN_USERGROUP_NAME}" to manage vnics in compartment "${OCI_CMPT_NAME}"\", \
                       \"Allow group "${OCI_FN_USERGROUP_NAME}" to inspect subnets in compartment "${OCI_CMPT_NAME}"\"]"
          echo $STATEMENTS > statements.json
          OCI_FN_USERGROUP_POLICY_ID=$(oci iam policy create --name Policy_for_$OCI_FN_USERGROUP_NAME \
                                     --description "A policy for the group ${OCI_FN_USERGROUP_NAME}" --statements file://`pwd`/statements.json \
                                     --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE --wait-interval-seconds 3 \
                                     -c ${OCI_TENANCY_OCID})
          echo Created policy Policy_for_$OCI_FN_USERGROUP_NAME.  Use the command: \'oci iam policy get --policy-id "${OCI_FN_USERGROUP_POLICY_ID}"\' if you want to view the policy.
          rm statements.json

          out "OCI_FN_USER_ID=${OCI_FN_USER_ID}"
          out "OCI_FN_USERGROUP_ID=${OCI_FN_USERGROUP_ID}"
          out "OCI_FN_USER_AUTH_TOKEN=\"${OCI_FN_USER_AUTH_TOKEN}\""
          sleep 30
          OCI_FN_USER_AUTH_TOKEN_OCID=$(oci iam auth-token  list --user-id ${OCI_FN_USER_ID}  --query 'data[0].id' --raw-output)
          out "OCI_FN_USER_AUTH_TOKEN_OCID=${OCI_FN_USER_AUTH_TOKEN_OCID}"
          out "OCI_FN_USERGROUP_POLICY_ID=${OCI_FN_USERGROUP_POLICY_ID}"

          

#Create Function App(a logical container for functions). Inside this app, we will create producer and consumer function
#Consumer function will be triggered by Kafka FnSink connector
          #Fn Context setup
            FN_CONTEXT=fn_oss_cntx_$OCI_CMPT_NAME
            fn delete context $FN_CONTEXT # just to make script idempotent, will throw error if given context does not exists
            fn create context $FN_CONTEXT --provider oracle 
            fn use context $FN_CONTEXT
            fn update context oracle.compartment-id $OCI_CMPT_ID
            fn update context api-url "https://functions.${OCI_CURRENT_REGION}.oraclecloud.com" # this is the OCI fn service url, again this is region specific
            fn update context oracle.profile $OCI_CLI_PROFILE # make sure to update your local ~./oci/config file with api and other credentials for this user
          
            #Docker setup for fn platform
            OCI_DOCKER_REGISTRY_URL="${OCI_CURRENT_REGION_CODE}.ocir.io"  # OCI docker registry URL. It is region specific e.g. for Ashburn iad.ocir.io
            FN_DOCKER_REPO_NAME=docker_repo_fn_oss_test # Your docker repo name...will be created when we push fn docker image
            FN_DOCKER_REPO_URL=$OCI_DOCKER_REGISTRY_URL/$OCI_TENANCY_NAME/$FN_DOCKER_REPO_NAME
            fn update context registry $FN_DOCKER_REPO_URL
            
          #Optional...if fn setup is done correctely this command should run without any issues.
            fn list apps 

          #You need to login, to allow you to push the function docker image to registry, when you build and deploy the function code
           docker logout $OCI_DOCKER_REGISTRY_URL
           n=0
           until [ $n -ge 10 ]; do
              echo "$OCI_FN_USER_AUTH_TOKEN" | docker login -u "$OCI_TENANCY_NAME/$OCI_FN_USERNAME" --password-stdin $OCI_DOCKER_REGISTRY_URL
              if [ $? -ne 0 ]; 
              then
                  {
                    n=$(($n + 1))
                    echo ["Failed docker login for OCI fn platform, trying again in 15 seconds, \
                          many times it takes time for user auth tokens to sync in with oci docker registry..."]
                    sleep 15
                  }
              else
                 echo "Docker Login Success!!"
                 break;
              fi
           done
          if [ $n -eq 10 ]; then
            echo "Could not login to oci docker registry after 10 attempts!!, returning from script"
            return
          fi

          #Create application for the function. This app is just logical container for both consumer and producer functions for our stream of product reviews
            FN_APP_NAME=fn_oss_app_test
            OCI_SUBNETID_LIST_JSON=[\"$OCI_SUBNET_1\"]
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
            fn config app $FN_APP_NAME OCI_USERNAME $OCI_FN_USERNAME
            #TODO use OCI secrets instead of config for auth token
            fn config app $FN_APP_NAME OCI_AUTH_TOKEN \"$OCI_FN_USER_AUTH_TOKEN\" 

            #Configs for Kafka Consumer function
            fn config app $FN_APP_NAME OCI_OBJECT_STORAGE_NAMESPACE $OCI_TENANCY_NAME
            fn config app $FN_APP_NAME OCI_OBJECT_STORAGE_REGION $OCI_CURRENT_REGION
            fn config app $FN_APP_NAME GOOD_REVIEWS_BUCKET_NAME $GOOD_REVIEWS_BUCKET_NAME 
            fn config app $FN_APP_NAME BAD_REVIEWS_BUCKET_NAME $BAD_REVIEWS_BUCKET_NAME
            fn config app $FN_APP_NAME UNPUBLISHBALE_WORD_LIST 'bad1,bad2,bad3,bad4'

          #Fetch the function code from github and actually deploy it in OCI Fn platform
            FN_REPO_NAME=OssFunctions
            rm -rf OssFunctions
            FN_GITHUB_URL="https://github.com/mayur-oci/${FN_REPO_NAME}.git"
            git clone -b zmqOop $FN_GITHUB_URL
            
            return
            
            fn -v deploy --app $FN_APP_NAME --no-bump ./$FN_REPO_NAME/ReviewConsumerFn   

            fn -v deploy --app $FN_APP_NAME --no-bump ./$FN_REPO_NAME/ReviewProducerFn

            fn update function $FN_APP_NAME review_consumer_fn --memory 512 --timeout 120
            fn update function $FN_APP_NAME review_producer_fn --memory 512 --timeout 120 

             

#Create Compute Instance for running dockerized Kafka Sink Connector for Oci Fn 
        SSH_PUBLIC_KEY_LOCATION="/Users/mraleras/sshkeypair1.key.pub" # Use your ssh public key file location here
        SSH_PRIVATE_KEY_LOCATION="/Users/mraleras/sshkeypair1.key.pvt" 

        COMPUTE_SHAPE='VM.Standard2.1'
        AD=$(oci iam availability-domain list --region ${OCI_CURRENT_REGION} --query "(data[?ends_with(name, '-3')] | [0].name) || data[0].name" --raw-output)
        echo availability-domain chosen for compute instance: $AD

        #Image ocid depends on region. Get image ocid from https://docs.cloud.oracle.com/en-us/iaas/images/image/96068886-76e5-4a48-af0a-fa7ed8466a25/
        #We are using Oracle Linux 8 from OCI phx region
        ORALCE_LINUX_IMAGE_OCID='ocid1.image.oc1.phx.aaaaaaaachy5qla6fy7pmkxf44r7ixoz6qybnkv7zsd3psxahihvbc54ahea'

        COMPUTE_OCID=$(oci compute instance launch \
                                -c ${OCI_CMPT_ID} \
                                --shape "${COMPUTE_SHAPE}" \
                                --display-name FnSinkConnectorVM \
                                --image-id ${ORALCE_LINUX_IMAGE_OCID} \
                                --ssh-authorized-keys-file "${SSH_PUBLIC_KEY_LOCATION}" \
                                --subnet-id ${OCI_SUBNET_1} \
                                --region ${OCI_CURRENT_REGION} \
                                --availability-domain "${AD}" \
                                --wait-for-state RUNNING \
                                --query "data.id" \
                                --raw-output) 
        #Get the Public IP
        COMPUTE_PUBLIC_IP=$(oci compute instance list-vnics \
            --instance-id "${COMPUTE_OCID}" \
            --region ${OCI_CURRENT_REGION} \
            --query 'data[0]."public-ip"' \
            --raw-output)
        echo 'The OCI Oracle Linux Compute Instance IP is' $COMPUTE_PUBLIC_IP    

        
        #Create Dynamic group and policy for your above instance to call consumer function review_consumer_fn
        MATCHING_RULE_FOR_DG_CI="ANY {instance.id = '${COMPUTE_OCID}'}"
        DG_CI_NAME=dg_for_kafka_fn_sink_${JobRunId}
        DG_CI_ID=$(oci --region $OCI_HOME_REGION iam dynamic-group create --description 'dg_for_kafka_fn_sink' --name ${DG_CI_NAME} --matching-rule "$MATCHING_RULE_FOR_DG_CI" --wait-for-state ACTIVE --query "data.id" --raw-output)

        DG_CI_POLICY="[\"Allow dynamic-group ${DG_CI_NAME} to manage all-resources in compartment ${OCI_CMPT_NAME} \"]"
        echo $DG_CI_POLICY > statements.json
        DG_CI_POLICY_ID=$(oci iam policy create -c $OCI_TENANCY_OCID --name "DG_CI_POLICY_$DG_CI_NAME" --description "A policy for instance" --statements file://`pwd`/statements.json --region ${OCI_HOME_REGION} --raw-output --query "data.id" --wait-for-state ACTIVE)
        echo Created policy ${DG_CI_POLICY_ID}.  Use the command: \'oci iam policy get --policy-id "${DG_CI_POLICY_ID}"\' if you want to view the policy.
        rm statements.json  

        out "COMPUTE_OCID=${COMPUTE_OCID}"
        out "COMPUTE_PUBLIC_IP=\"${COMPUTE_PUBLIC_IP}\""
        out "DG_CI_ID=${DG_CI_ID}" 
        out "DG_CI_POLICY_ID=${DG_CI_POLICY_ID}"    
        out "SSH_PRIVATE_KEY_LOCATION=\"${SSH_PRIVATE_KEY_LOCATION}\""                 

        sleep 60
        # transfer env values for docker
        echo OCI_TENANCY_NAME=${OCI_TENANCY_NAME} > env.json
        echo OCI_CURRENT_REGION=${OCI_CURRENT_REGION} >> env.json
        echo OCI_CMPT_ID=${OCI_CMPT_ID} >> env.json

        echo CONNECT_HARNESS_OCID=${OCI_CONNECT_HARNESS_ID} >> env.json
        echo OCI_STREAM_POOL_ID=${OCI_STREAM_POOL_ID} >> env.json
        echo OCI_STREAM_NAME=${OCI_STREAM_NAME} >> env.json
        echo OCI_STREAM_PARTITIONS_COUNT=${OCI_STREAM_PARTITIONS_COUNT} >> env.json

        echo OCI_USERNAME=${OCI_FN_USERNAME} >> env.json
        echo OCI_USER_AUTH_TOKEN=\"${OCI_FN_USER_AUTH_TOKEN}\" >> env.json

        echo FN_APP_NAME=${FN_APP_NAME} >> env.json
        echo FN_CONSUMER_FUNCTION_NAME=review_consumer_fn >> env.json
        echo FN_CONNECTOR_NAME="FnSinkConnector" >> env.json

        # SSH into the node, set it up JDK 8, maven, docker, configure firewall and start the Fn Sink Connector       
        cat env.json > kafkaConnector.sh 
        curl -O "https://raw.githubusercontent.com/mayur-oci/OssFunctions/zmqOop/AutomationScripts/SetupOciInstanceForFnSinkConnector.sh"
        cat SetupOciInstanceForFnSinkConnector.sh >> kafkaConnector.sh ; chmod 777 kafkaConnector.sh
        scp -i ${SSH_PRIVATE_KEY_LOCATION} -o ServerAliveInterval=60 -o "StrictHostKeyChecking no" ./kafkaConnector.sh opc@$COMPUTE_PUBLIC_IP:~/

        ssh -i ${SSH_PRIVATE_KEY_LOCATION} \
                      -n opc@${COMPUTE_PUBLIC_IP} -o ServerAliveInterval=60 \
                      -o "StrictHostKeyChecking no" \
                      "sudo sh ~/kafkaConnector.sh"  

        # If you want to see Fn Kafka Sink connector in action, you tail its logs as follows
        # ssh -i ${SSH_PRIVATE_KEY_LOCATION} \
        #               -n opc@${COMPUTE_PUBLIC_IP} -o ServerAliveInterval=60 \
        #               -o "StrictHostKeyChecking no" \
        #               'tail -f /tmp/kafka.log' &
              
        rm -rf env.json kafkaConnector.sh SetupOciInstanceForFnSinkConnector.sh ./${FN_REPO_NAME} 
        sleep 20 

#Invoke Consumer Function
        echo -n '{"reviewId": "REV_100", "time": 200010000000000, "productId": "PRODUCT_100", "reviewContent": "review content"}' | DEBUG=1 fn -v invoke $FN_APP_NAME review_consumer_fn 
        sleep 3

#Invoke Producer Function
        echo -n '{"reviewId": "REV_200", "time": 200010000000000, "productId": "PRODUCT_200", "reviewContent": "review content"}' | DEBUG=1 fn -v invoke $FN_APP_NAME review_producer_fn 

        echo -n '{"reviewId": "REV_300", "time": 300010000000100, "productId": "PRODUCT_300", "reviewContent": "review content bad2"}' | DEBUG=1 fn -v invoke $FN_APP_NAME review_producer_fn

#Checking if objects are created in the buckets
       sleep 20
       oci os object list -bn ${GOOD_REVIEWS_BUCKET_NAME}
       oci os object list -bn ${BAD_REVIEWS_BUCKET_NAME}

       return

#Delete all resources in cmpt. 
    OCID_CMPT_STACK=$(oci resource-manager stack create-from-compartment  --compartment-id ${OCI_TENANCY_OCID} --config-source-compartment-id ${OCI_CMPT_ID} \
    --config-source-region PHX --terraform-version "0.13.x"\
    --display-name "Stack_${OCI_CMPT_NAME}" --description 'Stack From Compartment ${OCI_CMPT_NAME}' --wait-for-state SUCCEEDED --query "data.resources[0].identifier" --raw-output)
    echo $OCID_CMPT_STACK

    oci resource-manager job create-destroy-job  --execution-plan-strategy 'AUTO_APPROVED'  --stack-id ${OCID_CMPT_STACK} --wait-for-state SUCCEEDED
    # twice since it fails sometimes and running it twice is idempotent
    oci resource-manager job create-destroy-job  --execution-plan-strategy 'AUTO_APPROVED'  --stack-id ${OCID_CMPT_STACK} --wait-for-state SUCCEEDED

    oci resource-manager stack delete --stack-id ${OCID_CMPT_STACK} --force --wait-for-state DELETED

    oci iam policy delete --policy-id ${OCI_FN_DG_AND_FAAS_POLICY_ID} --force --wait-for-state INACTIVE
    oci iam policy delete --policy-id ${OCI_FN_USERGROUP_POLICY_ID} --force --wait-for-state INACTIVE
    oci iam policy delete --policy-id ${DG_CI_POLICY_ID} --force --wait-for-state INACTIVE

    oci iam dynamic-group delete --dynamic-group-id ${OCI_FN_DG_ID} --force --wait-for-state DELETED
    oci iam dynamic-group delete --dynamic-group-id ${DG_CI_ID} --force --wait-for-state DELETED

    oci iam group remove-user --group-id ${OCI_FN_USERGROUP_ID} --user-id ${OCI_FN_USER_ID} --force 
    oci iam user delete --user-id ${OCI_FN_USER_ID} --force --wait-for-state INACTIVE
    oci iam group delete --group-id ${OCI_FN_USERGROUP_ID} --force --wait-for-state INACTIVE

    oci iam compartment delete -c ${OCI_CMPT_ID} --force --wait-for-state SUCCEEDED

    exit
########################
    mkdir tf_${OCI_CMPT_NAME}
    export TF_VAR_region=${OCI_CURRENT_REGION}
    terraform-provider-oci -command=export -compartment_id=${OCI_CMPT_ID} -output_path=./tf_${OCI_CMPT_NAME}/
    cd tf_${OCI_CMPT_NAME}
    terraform init 
    terraform destroy

    #delete compute
    oci iam policy delete --policy-id ${DG_CI_POLICY_ID} --force --wait-for-state INACTIVE
    oci iam dynamic-group delete --dynamic-group-id ${DG_CI_ID} --force --wait-for-state DELETED
    oci compute instance terminate  --instance-id ${COMPUTE_OCID} --force --wait-for-state TERMINATED
    

    #delete stream
    oci streaming admin connect-harness delete --connect-harness-id ${OCI_CONNECT_HARNESS_ID} --force --wait-for-state DELETED
    oci streaming admin stream delete --stream-id ${OCI_STREAM_ID} --force --wait-for-state DELETED
    oci streaming admin stream-pool delete --stream-pool-id ${OCI_STREAM_POOL_ID} --force --wait-for-state DELETED

    # delete buckets 
    while true 
    do
      echo "Welcome $i times."
      objectName=$(oci os object list -bn ${GOOD_REVIEWS_BUCKET_NAME} --all --raw-output  --query "data[0].name")
      if [ ! -z "$objectName" ]; then
          oci os object delete -bn ${GOOD_REVIEWS_BUCKET_NAME} --object-name $objectName --force
      else
         break
      fi        
    done
    oci os bucket delete -bn ${GOOD_REVIEWS_BUCKET_NAME} --force

    while true
    do
      echo "Welcome $i times."
      objectName=$(oci os object list -bn ${BAD_REVIEWS_BUCKET_NAME} --all --raw-output  --query "data[0].name")
      if [ ! -z "$objectName" ]; then
          oci os object delete -bn ${BAD_REVIEWS_BUCKET_NAME} --object-name $objectName --force
      else
         break
      fi        
    done    
    oci os bucket delete -bn ${BAD_REVIEWS_BUCKET_NAME} --force

    # oci os object list -bn ${GOOD_REVIEWS_BUCKET_NAME} --all --raw-output  --query 'data[1].name'
    # oci os bucket get --bucket-name ${BAD_REVIEW_BUCKET_NAME} --fields approximateCount --raw-output --query 'data."approximate-count"'


    # TODO delete fn and fn app
    fn delete function $FN_APP_NAME review_producer_fn
    fn delete function $FN_APP_NAME review_consumer_fn
    fn delete app $FN_APP_NAME -r --force

    oci iam policy delete --policy-id ${OCI_FN_DG_AND_FAAS_POLICY_ID} --force --wait-for-state INACTIVE
    oci iam dynamic-group delete --dynamic-group-id ${OCI_FN_DG_ID} --force --wait-for-state DELETED
    
    #delete user and user-group
    oci iam policy delete --policy-id ${OCI_FN_USERGROUP_POLICY_ID} --force --wait-for-state INACTIVE
    oci iam auth-token delete --auth-token-id ${OCI_FN_USER_AUTH_TOKEN_OCID} --user-id ${OCI_FN_USER_ID} --force

    oci iam user delete --user-id ${OCI_FN_USER_ID} --force --wait-for-state INACTIVE
    oci iam group delete --group-id ${OCI_FN_USERGROUP_ID} --force --wait-for-state INACTIVE

    oci network route-table delete --rt-id ${OCI_FN_VCN_ROUTE_TABLE_ID} --force --wait-for-state TERMINATED
    oci network security-list delete --security-list-id ${OCI_FN_VCN_SECURITY_LIST_ID} --force --wait-for-state TERMINATED
    oci network internet-gateway delete --ig-id ${OCI_FN_INTERNET_GATEWAY_ID} --force --wait-for-state TERMINATED
    oci network subnet delete --subnet-id ${OCI_SUBNET_1} --force --wait-for-state TERMINATING
    oci network subnet delete --subnet-id ${OCI_SUBNET_2} --force --wait-for-state TERMINATING
    oci network subnet delete --subnet-id ${OCI_SUBNET_3} --force --wait-for-state TERMINATING


    oci network vcn delete --vcn-id ${OCI_FN_VCN_ID} --force --wait-for-state TERMINATING

    oci iam compartment delete -c ${OCI_CMPT_ID} --force --wait-for-state SUCCEEDED



