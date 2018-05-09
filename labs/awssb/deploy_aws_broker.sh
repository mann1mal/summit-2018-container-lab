#!/bin/bash

#
# Helper script for deploying the AWS Broker to an existing OpenShift cluster
# using an OpenShift template.
#


#
# VERIFY and UPDATE the variables below
#
CLUSTER_ADMIN_USER="system:admin"
TEMPLATE_FILE="./deploy-awsservicebroker.template.yaml"
DOCKERHUB_ORG=${DOCKERHUB_ORG:-"awsservicebroker"} # Dockerhub organization where AWS APBs can be found, default 'awsservicebroker'
ENABLE_BASIC_AUTH="false"

#
# Login as the CLUSTER_ADMIN_USER
#
oc login -u ${CLUSTER_ADMIN_USER}

#
# Get the BROKER_CA_CERT
#
BROKER_CA_CERT=`oc get secret -n kube-service-catalog -o go-template='{{ range .items }}{{ if eq .type "kubernetes.io/service-account-token" }}{{ index .data "service-ca.crt" }}{{end}}{{"\n"}}{{end}}' | awk NF | tail -n 1`
if [ "${BROKER_CA_CERT}" == "" ]; then
    echo -e "\nUnable to set the BROKER_CA_CERT variable!"
    echo -e "Please VERIFY that CLUSTER_ADMIN_USER is set to a user with cluster admin privileges\n"
    exit
fi

#
# creating aws-service-broker project
#
oc new-project aws-service-broker

#
# Creating OpenSSL certificates to use with AWS Brokawser and etcd store
#
mkdir -p /tmp/etcd-cert
openssl req -nodes -x509 -newkey rsa:4096 -keyout /tmp/etcd-cert/key.pem -out /tmp/etcd-cert/cert.pem -days 365 -subj "/CN=asb-etcd.ansible-service-broker.svc"
openssl genrsa -out /tmp/etcd-cert/MyClient1.key 2048 \
&& openssl req -new -key /tmp/etcd-cert/MyClient1.key -out /tmp/etcd-cert/MyClient1.csr -subj "/CN=client" \
&& openssl x509 -req -in /tmp/etcd-cert/MyClient1.csr -CA /tmp/etcd-cert/cert.pem -CAkey /tmp/etcd-cert/key.pem -CAcreateserial -out /tmp/etcd-cert/MyClient1.pem -days 1024

ETCD_CA_CERT=$(cat /tmp/etcd-cert/cert.pem | base64)
BROKER_CLIENT_CERT=$(cat /tmp/etcd-cert/MyClient1.pem | base64)
BROKER_CLIENT_KEY=$(cat /tmp/etcd-cert/MyClient1.key | base64)

#
# Deploy the Broker with parameters
#
cat $TEMPLATE_FILE \
  | oc process \
  -n aws-service-broker \
  -p DOCKERHUB_ORG="$DOCKERHUB_ORG" \
  -p ENABLE_BASIC_AUTH="$ENABLE_BASIC_AUTH" \
  -p ETCD_TRUSTED_CA_FILE=/var/run/etcd-auth-secret/ca.crt \
  -p BROKER_CLIENT_CERT_PATH=/var/run/aws-asb-etcd-auth/client.crt \
  -p BROKER_CLIENT_KEY_PATH=/var/run/aws-asb-etcd-auth/client.key \
  -p ETCD_TRUSTED_CA="$ETCD_CA_CERT" \
  -p BROKER_CLIENT_CERT="$BROKER_CLIENT_CERT" \
  -p BROKER_CLIENT_KEY="$BROKER_CLIENT_KEY" \
  -p NAMESPACE=aws-service-broker \
  -p BROKER_CA_CERT="$BROKER_CA_CERT" -f - | oc create -f -
if [ "$?" -ne 0 ]; then
  echo "Error processing template and creating deployment"
  exit
fi
