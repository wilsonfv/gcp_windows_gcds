#!/bin/bash

function log() {
    STAMP=$(date +'%Y-%m-%d %H:%M:%S %Z')
    printf "\n%s    %s\n" "${STAMP}" "$1"
}

function tidy_up() {
    if [[ $(gcloud compute instances list \
            --project=${GCP_PROJECT_ID} \
            --filter="NAME=${GCE_WIN_VM_NAME}" \
            --format="csv(NAME)[no-heading]") ]]; then
        gcloud compute instances delete ${GCE_WIN_VM_NAME} --zone ${GCE_WIN_VM_ZONE} --project=${GCP_PROJECT_ID} -q
    fi

    if [[ $(gcloud compute networks list \
            --project=${GCP_PROJECT_ID} \
            --filter="name=${VPC_NAME}" \
            --format="csv(NAME)[no-heading]") ]]; then

        for FIREWALL_RULE in $(gcloud compute firewall-rules list \
                                --project=${GCP_PROJECT_ID} \
                                --format="csv(NAME)[no-heading]")
        do
            gcloud compute firewall-rules delete ${FIREWALL_RULE} --project=${GCP_PROJECT_ID} -q
        done

        gcloud compute networks delete ${VPC_NAME} --project=${GCP_PROJECT_ID} -q
    fi
}

# **********************************************************************************************
# Main Flow
# **********************************************************************************************

set -e

export SCRIPT_DIR=$(dirname "$0")
export GCP_PROJECT_ID=${SERVICE_PROJECT_ID}
export VPC_NAME=default
export GCE_WIN_VM_NAME=gce-windows-gcds
export GCE_WIN_VM_ZONE=europe-west1-b

log "authenticate as service project service account"
export GOOGLE_APPLICATION_CREDENTIALS=${SERVICE_PROJECT_GCP_SA_KEY_JSON}
gcloud auth activate-service-account --key-file ${GOOGLE_APPLICATION_CREDENTIALS}

tidy_up

gcloud compute networks create ${VPC_NAME} \
    --subnet-mode=auto \
    --bgp-routing-mode=global

gcloud compute firewall-rules create ${VPC_NAME}-fw --network ${VPC_NAME} --allow tcp:22,tcp:3389,icmp --enable-logging

gcloud compute instances create ${GCE_WIN_VM_NAME} \
    --zone ${GCE_WIN_VM_ZONE} \
    --image-project windows-cloud \
    --image-family windows-2016 \
    --machine-type n1-standard-4 \
    --boot-disk-size 200 \
    --boot-disk-type pd-standard

sleep 120

gcloud compute reset-windows-password ${GCE_WIN_VM_NAME} --zone ${GCE_WIN_VM_ZONE} -q
