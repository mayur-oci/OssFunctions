#Create FunctionApp(logical container for functions). Inside this app we will create producer and consumer function
#Consumer function is triggered by Kafka FnSink connector

          cd /Users/mraleras/OssFunctions/ReviewConsumerFn
          OCI_CMPT_ID=ocid1.compartment.oc1..aaaaaaaa2z4wup7a4enznwxi3mkk55cperdk3fcotagepjnan5utdb3tvakq
          OCI_CLI_PROFILE=DEFAULT
          OCI_SUBNET_1=ocid1.subnet.oc1.phx.aaaaaaaagqtri6ot7bdxqf23wcc5gcb525g2v44iyj2zggrzcdhcmmmp62ma
          OCI_CMPT_NAME=mayursandbox
          OCI_CURRENT_REGION=us-phoenix-1
          TAIL_URL=tcp://logs5.papertrailapp.com:45170

          OCI_CMPT_OCID=$OCI_CMPT_ID # OCID of OCI compartment where you want your function to reside
          OCI_USER_ID='mayur.raleraskar@oracle.com' # $OCI_FN_GROUP_ID
          OCI_AUTH_TOKEN='2m{s4WTCXysp:o]tGx4K' # "$OCI_FN_USER_AUTH_TOKEN"  Your OCI generated auth token
          OCI_DOCKER_REGISTRY_URL="phx.ocir.io"  # OCI dokcer registry URL. It is region specific e.g. for Ashburn iad.ocir.io
          OCI_TENANCY_NAME=intrandallbarnes # $OCI_FN_TENANCY Your OCI tenancy name
          GOOD_REVIEW_BUCKET_NAME=goodRevBucket
          BAD_REVIEWS_BUCKET_NAME=badRevBucket

          FN_CONTEXT=fn_oss_cntx_0
          FN_OCI_PLATFORM_URL='https://functions.us-phoenix-1.oraclecloud.com' # this is the OCI fn service url, again this is region specific
          FN_DOCKER_REPO_NAME=docker_repo_fn_oss_test # Your docker repo name...will be created when we push fn docker image
          FN_DOCKER_REPO_URL=$OCI_DOCKER_REGISTRY_URL/$OCI_TENANCY_NAME/$FN_DOCKER_REPO_NAME
          FN_APP_NAME=fn_oss_app_test # Name for the application for the function. Application is a logical container for functions in Oracle Cloud Function platform.
          FN_PRODUCER_FUNCTION_NAME=ReviewProducerFn
          FN_CONSUMER_FUNCTION_NAME=ReviewConsumerFn
          FN_GITHUB_REPO_NAME=oci_fn_jira_integration
          FN_GITHUB_URL="https://github.com/mayur-oci/$FN_GITHUB_REPO_NAME.git"


          fn delete context $FN_CONTEXT # just to make script idempotent
          fn create context $FN_CONTEXT --provider oracle
          fn use context $FN_CONTEXT
          fn update context oracle.compartment-id $OCI_CMPT_OCID
          fn update context api-url $FN_OCI_PLATFORM_URL
          fn update context registry $FN_DOCKER_REPO_URL
          fn update context oracle.profile $OCI_CLI_PROFILE # make sure to update your local ~./oci/config file with api and other credentials for this user

          fn list apps

          # You need to login, to allow you to push the function docker image to registry, when you build and deploy the function code
          docker login -u $OCI_TENANCY_NAME/$OCI_USER_ID -p $OCI_AUTH_TOKEN $OCI_DOCKER_REGISTRY_URL

          # Create application for the function
          OCI_SUBNETID_LIST_JSON=[\"$OCI_SUBNET_1\"]
          # this app is just logical container for both consumer and producer functions for our stream of product reviews
          #fn delete app -f -r $FN_APP_NAME
          fn update app $FN_APP_NAME --syslog-url $TAIL_URL --annotation oracle.com/oci/subnetIds=$OCI_SUBNETID_LIST_JSON
          sleep 5

          fn config app $FN_APP_NAME OCI_FN_TENANCY $OCI_FN_TENANCY
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

          fn config app $FN_APP_NAME LOCK_BUCKET_NAME $BAD_REVIEWS_BUCKET_OCID
          fn config app $FN_APP_NAME LOCK_BUCKET_OCID $BAD_REVIEWS_BUCKET_OCID
          fn config app $FN_APP_NAME LOCK_OBJECT_NAME LOCK_OBJECT
          fn config app $FN_APP_NAME MAX_CONSUMER_PROCESS_COUNT 5
          fn config app $FN_APP_NAME UNPUBLISHBALE_WORD_LIST 'bad1,bad2,bad3,bad4'

          fn -v deploy --app $FN_APP_NAME --no-bump .
          fn update function $FN_APP_NAME review_consumer_fn --memory 512 --timeout 120

