#!/bin/bash

function log() {
    STAMP=$(date +'%Y-%m-%d %H:%M:%S %Z')
    printf "\n%s    %s\n" "${STAMP}" "$1"
}

function get_tf_binary() {
    ROOT_DIR=$1
    PRODUCT=$2
    PRODUCT_VERSION=$3
    OS_VERSION=$4

    FILE_NAME=${PRODUCT}_${PRODUCT_VERSION}_${OS_VERSION}.zip
    URL=https://releases.hashicorp.com/${PRODUCT}/${PRODUCT_VERSION}/${FILE_NAME}

    log "downloading ${URL}"
    curl -k -s ${URL} \
        -o ${ROOT_DIR}/${FILE_NAME}

    unzip -q -o ${ROOT_DIR}/${FILE_NAME} -d ${ROOT_DIR}
    rm -f ${ROOT_DIR}/${FILE_NAME}
}

function create_gcp_sa()
{
    for SA_ID in "${SERVICE_PROJECT_SA_ID[@]}"
    do
        if [[ ! $(gcloud iam service-accounts list \
                    --filter="EMAIL=${SA_ID}@${SERVICE_PROJECT_SA_SUFFIX}" \
                    --format="csv(EMAIL)[no-heading]" \
                    --project=${SERVICE_PROJECT_ID}) ]]; then
            gcloud iam service-accounts create ${SA_ID} \
                --description="${SA_ID}" \
                --display-name="${SA_ID}" \
                --project=${SERVICE_PROJECT_ID}
        fi
    done
}

function delete_gcp_sa()
{
    for SA_ID in "${SERVICE_PROJECT_SA_ID[@]}"
    do
        if [[ $(gcloud iam service-accounts list \
                    --filter="EMAIL=${SA_ID}@${SERVICE_PROJECT_SA_SUFFIX}" \
                    --format="csv(EMAIL)[no-heading]" \
                    --project=${SERVICE_PROJECT_ID}) ]]; then
            gcloud iam service-accounts delete "${SA_ID}@${SERVICE_PROJECT_SA_SUFFIX}" \
                --project=${SERVICE_PROJECT_ID}
        fi
    done
}

function tidy_up() {
    log "clear up environment"

    if [[ -d ${TF_BINARY_DIR} ]]; then
        rm -rf ${TF_BINARY_DIR}
    fi

    if [[ -d ${SCRIPT_DIR}/.terraform ]]; then
        rm -rf ${SCRIPT_DIR}/.terraform
    fi

    if [[ -d ${TF_GROUP_WORKING_DIR}/.terraform ]]; then
        rm -rf ${TF_GROUP_WORKING_DIR}/.terraform
    fi

    if [[ -d ${TF_MEMBERSHIP_WORKING_DIR}/.terraform ]]; then
        rm -rf ${TF_MEMBERSHIP_WORKING_DIR}/.terraform
    fi

    log "authenticate as service project service account"
    gcloud auth activate-service-account --key-file ${SERVICE_PROJECT_GCP_SA_KEY_JSON}

    if [[ $(gcloud compute instances list \
            --project=${SERVICE_PROJECT_ID} \
            --filter="NAME=${SERVICE_PROJECT_VM_NAME}" \
            --format="csv(name)[no-heading]") ]]; then
        gcloud compute instances delete ${SERVICE_PROJECT_VM_NAME} --zone ${SERVICE_PROJECT_VM_ZONE} --project=${SERVICE_PROJECT_ID} -q
    fi

#    delete_gcp_sa

#    if [[ $(gcloud compute networks list \
#            --project=${SERVICE_PROJECT_ID} \
#            --filter="name=${SERVICE_PROJECT_VPC_NAME}" \
#            --format="csv(NAME)[no-heading]") ]]; then
#
#        for FIREWALL_RULE in $(gcloud compute firewall-rules list \
#                                --project=${SERVICE_PROJECT_ID} \
#                                --format="csv(NAME)[no-heading]")
#        do
#            gcloud compute firewall-rules delete ${FIREWALL_RULE} --project=${SERVICE_PROJECT_ID} -q
#        done
#
#        gcloud compute networks delete ${VPC_NAME} --project=${GCP_PROJECT_ID} -q
#    fi

    log "authenticate as share project service account"
    gcloud auth activate-service-account --key-file ${SHARE_PROJECT_GCP_SA_KEY_JSON}

    if [[ $(gcloud compute images list \
                --project ${SHARE_PROJECT_ID} \
                --filter="name=${SHARE_PROJECT_CUSTOM_IMAGE_NAME}") ]]; then
        gcloud compute images delete ${SHARE_PROJECT_CUSTOM_IMAGE_NAME} --project ${SHARE_PROJECT_ID} -q
    fi
}

# **********************************************************************************************
# Main Flow
# **********************************************************************************************

export SCRIPT_DIR=$(dirname "$0")
export TF_BINARY_DIR=${SCRIPT_DIR}/tf_binary
export TF_GROUP_WORKING_DIR=${SCRIPT_DIR}/terraform_deployment_custom_group
export TF_MEMBERSHIP_WORKING_DIR=${SCRIPT_DIR}/terraform_deployment_custom_group_membership
export SHARE_PROJECT_ID=${SHARE_PROJECT_ID}
export SHARE_PROJECT_GCP_SA_KEY_JSON=${SHARE_PROJECT_GCP_SA_KEY_JSON}
export SERVICE_PROJECT_ID=${SERVICE_PROJECT_ID}
export SERVICE_PROJECT_GCP_SA_KEY_JSON=${SERVICE_PROJECT_GCP_SA_KEY_JSON}
export SERVICE_PROJECT_USER_SA="packer"
export SERVICE_PROJECT_SA_SUFFIX="${SERVICE_PROJECT_ID}.iam.gserviceaccount.com"
export SERVICE_PROJECT_SA_ID=(
    "image-sa1"
    "image-sa2"
    "vpc1-sa1"
    "vpc1-sa2"
    "vpc2-sa1"
    "vpc2-sa2"
    "${SERVICE_PROJECT_USER_SA}"
)
export SHARE_PROJECT_CUSTOM_IMAGE_NAME=custom-image
export SERVICE_PROJECT_VM_NAME=temp-vm
export SERVICE_PROJECT_VM_REGION=europe-west1
export SERVICE_PROJECT_VM_ZONE=${SERVICE_PROJECT_VM_REGION}-b
export SERVICE_PROJECT_VPC_NAME=default

tidy_up

log "download terraform binary"
mkdir -p ${TF_BINARY_DIR}
get_tf_binary ${TF_BINARY_DIR} terraform                        0.12.13 darwin_amd64
get_tf_binary ${TF_BINARY_DIR} terraform-provider-google        2.17.0 darwin_amd64
get_tf_binary ${TF_BINARY_DIR} terraform-provider-google-beta   3.49.0 darwin_amd64

log "authenticate as service project service account"
export GOOGLE_APPLICATION_CREDENTIALS=${SERVICE_PROJECT_GCP_SA_KEY_JSON}
gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}

log "prepare custom_groups.auto.tfvars.json to create user-defined google groups"
cat >${TF_GROUP_WORKING_DIR}/custom_groups.auto.tfvars.json<<EOF
{
  "custom_groups": {
    "image": {
      "display_name": "gcp.custom-group.image",
      "group_key_id": "gcp.custom-group.image@imok2.page"
    },
    "vpc1": {
      "display_name": "gcp.custom-group.vpc1",
      "group_key_id": "gcp.custom-group.vpc1@imok2.page"
    },
    "vpc2": {
      "display_name": "gcp.custom-group.vpc2",
      "group_key_id": "gcp.custom-group.vpc2@imok2.page"
    }
  }
}
EOF
cat ${TF_GROUP_WORKING_DIR}/custom_groups.auto.tfvars.json

export TF_DATA_DIR=${TF_GROUP_WORKING_DIR}

log "terraform init ${TF_GROUP_WORKING_DIR}"
${TF_BINARY_DIR}/terraform init \
    -no-color \
    -backend-config="path=${TF_GROUP_WORKING_DIR}/terraform_state" \
    ${TF_GROUP_WORKING_DIR}

log "terraform apply ${TF_GROUP_WORKING_DIR} to create user-defined google groups"
${TF_BINARY_DIR}/terraform apply \
    -no-color \
    -var-file "${TF_GROUP_WORKING_DIR}/custom_groups.auto.tfvars.json" \
    -auto-approve ${TF_GROUP_WORKING_DIR}

log "create service project service accounts"
create_gcp_sa

log "prepare custom_groups_memberships.auto.tfvars.json to add user-defined GCP service accounts to groups"
cat >${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json<<EOF
{
  "custom_groups_memberships": {
    "gcp.custom-group.image@imok2.page": [
        "image-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "image-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ],
    "gcp.custom-group.vpc1@imok2.page": [
        "vpc1-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "vpc1-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ],
    "gcp.custom-group.vpc2@imok2.page": [
        "vpc2-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "vpc2-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ]
  }
}
EOF
cat ${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json

export TF_DATA_DIR=${TF_MEMBERSHIP_WORKING_DIR}

log "terraform init ${TF_MEMBERSHIP_WORKING_DIR}"
${TF_BINARY_DIR}/terraform init \
    -no-color \
    -backend-config="path=${TF_MEMBERSHIP_WORKING_DIR}/terraform_state" \
    ${TF_MEMBERSHIP_WORKING_DIR}

log "terraform apply ${TF_MEMBERSHIP_WORKING_DIR} to add user-defined GCP service accounts to groups"
${TF_BINARY_DIR}/terraform apply \
    -no-color \
    -var-file "${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json" \
    -auto-approve ${TF_MEMBERSHIP_WORKING_DIR}

log "authenticate as share project service account"
gcloud auth activate-service-account --key-file ${SHARE_PROJECT_GCP_SA_KEY_JSON}

log "create a custom compute image in share project"
gcloud compute images create ${SHARE_PROJECT_CUSTOM_IMAGE_NAME} \
  --source-image=cos-85-13310-1209-17 \
  --source-image-project=cos-cloud \
  --family=${SHARE_PROJECT_CUSTOM_IMAGE_NAME} \
  --project ${SHARE_PROJECT_ID}

log "authenticate as service project service account"
gcloud auth activate-service-account --key-file ${SERVICE_PROJECT_GCP_SA_KEY_JSON}

#log "create a default vpc in service project"
#gcloud compute networks create ${SERVICE_PROJECT_VPC_NAME} \
#    --subnet-mode=auto \
#    --bgp-routing-mode=global
#gcloud compute firewall-rules create ${SERVICE_PROJECT_VPC_NAME}-fw --network ${SERVICE_PROJECT_VPC_NAME} --allow tcp:22,tcp:3389,icmp --enable-logging

log "allow service project ${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX} to create VM"
gcloud projects add-iam-policy-binding ${SERVICE_PROJECT_ID} --member="serviceAccount:${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}"  --role='roles/compute.instanceAdmin.v1'
gcloud projects add-iam-policy-binding ${SERVICE_PROJECT_ID} --member="serviceAccount:${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}"  --role='roles/iam.serviceAccountUser'

log "using impersonate service account to run as "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}", create a VM in service project using custom image from share project"
log "we will expect to see permission denied Required 'compute.images.useReadOnly' error"
gcloud compute instances create ${SERVICE_PROJECT_VM_NAME} \
    --zone ${SERVICE_PROJECT_VM_ZONE} \
    --image-project ${SHARE_PROJECT_ID} \
    --image-family ${SHARE_PROJECT_CUSTOM_IMAGE_NAME} \
    --machine-type f1-micro \
    --boot-disk-size 200 \
    --boot-disk-type pd-standard \
    --preemptible \
    --impersonate-service-account "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" \
    --project=${SERVICE_PROJECT_ID}

log "add ${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX} to custom groups image and vpc1"
log "prepare custom_groups_memberships.auto.tfvars.json to add ${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX} to custom groups image and vpc1"
cat >${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json<<EOF
{
  "custom_groups_memberships": {
    "gcp.custom-group.image@imok2.page": [
        "image-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "image-sa2@${SERVICE_PROJECT_SA_SUFFIX}",
        "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}"
    ],
    "gcp.custom-group.vpc1@imok2.page": [
        "vpc1-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "vpc1-sa2@${SERVICE_PROJECT_SA_SUFFIX}",
        "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}"
    ],
    "gcp.custom-group.vpc2@imok2.page": [
        "vpc2-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "vpc2-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ]
  }
}
EOF
cat ${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json

export TF_DATA_DIR=${TF_MEMBERSHIP_WORKING_DIR}

log "terraform init ${TF_MEMBERSHIP_WORKING_DIR}"
${TF_BINARY_DIR}/terraform init \
    -no-color \
    -backend-config="path=${TF_MEMBERSHIP_WORKING_DIR}/terraform_state" \
    ${TF_MEMBERSHIP_WORKING_DIR}

log "terraform apply ${TF_MEMBERSHIP_WORKING_DIR} to add ${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX} to custom groups image and vpc1"
${TF_BINARY_DIR}/terraform apply \
    -no-color \
    -var-file "${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json" \
    -auto-approve ${TF_MEMBERSHIP_WORKING_DIR}

log "authenticate as share project service account"
gcloud auth activate-service-account --key-file ${SHARE_PROJECT_GCP_SA_KEY_JSON}

log "grant roles/compute.imageUser to the custom group"
gcloud projects add-iam-policy-binding ${SHARE_PROJECT_ID} --member="group:gcp.custom-group.image@imok2.page" --role='roles/compute.imageUser'

log "authenticate as service project service account"
gcloud auth activate-service-account --key-file ${SERVICE_PROJECT_GCP_SA_KEY_JSON}

log "using impersonate service account to run as "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}", create a VM in service project using custom image from share project"
log "after roles/compute.imageUser granted to the custom group, service project SA is now able to use custom image to create VM"
gcloud compute instances create ${SERVICE_PROJECT_VM_NAME} \
    --zone ${SERVICE_PROJECT_VM_ZONE} \
    --image-project ${SHARE_PROJECT_ID} \
    --image-family ${SHARE_PROJECT_CUSTOM_IMAGE_NAME} \
    --machine-type f1-micro \
    --boot-disk-size 200 \
    --boot-disk-type pd-standard \
    --preemptible \
    --impersonate-service-account "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" \
    --project=${SERVICE_PROJECT_ID}

if [[ $(gcloud compute instances list \
        --project=${SERVICE_PROJECT_ID} \
        --filter="NAME=${SERVICE_PROJECT_VM_NAME}" \
        --format="csv(name)[no-heading]") ]]; then
    log "since "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" is able to access the custom image from share project, we will delete the VM"
    gcloud compute instances delete ${SERVICE_PROJECT_VM_NAME} --zone ${SERVICE_PROJECT_VM_ZONE} --project=${SERVICE_PROJECT_ID} -q
fi

log "remove "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" from custom groups so that it will lose permission access to the share image"
log "prepare custom_groups_memberships.auto.tfvars.json to remove "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" from custom groups"
cat >${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json<<EOF
{
  "custom_groups_memberships": {
    "gcp.custom-group.image@imok2.page": [
        "image-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "image-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ],
    "gcp.custom-group.vpc1@imok2.page": [
        "vpc1-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "vpc1-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ],
    "gcp.custom-group.vpc2@imok2.page": [
        "vpc2-sa1@${SERVICE_PROJECT_SA_SUFFIX}",
        "vpc2-sa2@${SERVICE_PROJECT_SA_SUFFIX}"
    ]
  }
}
EOF
cat ${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json

export TF_DATA_DIR=${TF_MEMBERSHIP_WORKING_DIR}

log "terraform init ${TF_MEMBERSHIP_WORKING_DIR}"
${TF_BINARY_DIR}/terraform init \
    -no-color \
    -backend-config="path=${TF_MEMBERSHIP_WORKING_DIR}/terraform_state" \
    ${TF_MEMBERSHIP_WORKING_DIR}

log "terraform apply ${TF_MEMBERSHIP_WORKING_DIR} to remove "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" from custom groups"
${TF_BINARY_DIR}/terraform apply \
    -no-color \
    -var-file "${TF_MEMBERSHIP_WORKING_DIR}/custom_groups_memberships.auto.tfvars.json" \
    -auto-approve ${TF_MEMBERSHIP_WORKING_DIR}

log "wait 120 seconds for gcp to propagate the state that ${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX} has removed from the custom group and lost permission to the share image"
sleep 120

log "authenticate as service project service account"
gcloud auth activate-service-account --key-file ${SERVICE_PROJECT_GCP_SA_KEY_JSON}

log "using impersonate service account to run as "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}", create a VM in service project using custom image from share project"
log "since "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" has been removed from custom groups, we will expect to see permission denied Required 'compute.images.useReadOnly' error"
gcloud compute instances create ${SERVICE_PROJECT_VM_NAME} \
    --zone ${SERVICE_PROJECT_VM_ZONE} \
    --image-project ${SHARE_PROJECT_ID} \
    --image-family ${SHARE_PROJECT_CUSTOM_IMAGE_NAME} \
    --machine-type f1-micro \
    --boot-disk-size 200 \
    --boot-disk-type pd-standard \
    --preemptible \
    --impersonate-service-account "${SERVICE_PROJECT_USER_SA}@${SERVICE_PROJECT_SA_SUFFIX}" \
    --project=${SERVICE_PROJECT_ID}

tidy_up

#log "terraform destroy"
#${TF_BINARY_DIR}/terraform destroy \
#    -auto-approve ${TF_GROUP_WORKING_DIR}