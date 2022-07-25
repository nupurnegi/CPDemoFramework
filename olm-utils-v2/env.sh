#!/bin/sh
SERVER=

# APITOKEN
API_TOKEN=

# OR

# Username and password
KUBEADMIN_USER=
KUBEADMIN_PASS=

# ICR KEY
# Please enter the ICR KEY if the server value is pointing to IBM cloud ROKS cluster.
ICR_KEY=


# SCRIPT
#Pod login and auto login to oc cluster from runutils
if  [ -n "$KUBEADMIN_USER" ] && [ -n "$KUBEADMIN_PASS" ]
    then
        alias oclogin_auto="run_utils login-to-ocp -u ${KUBEADMIN_USER} -p ${KUBEADMIN_PASS} --server=${SERVER}";
        alias pod_login="oc login -u ${KUBEADMIN_USER} -p ${KUBEADMIN_PASS} --server ${SERVER}";
    else
        if  [ -z "$API_TOKEN" ]
            then
                    echo "Invalid api token, please check env.sh file";
            else
                alias pod_login="oc login --token=${API_TOKEN} --server=${SERVER}";
                alias oclogin_auto="run_utils login-to-ocp --token=${API_TOKEN} --server=${SERVER}";
        fi
fi
# Pod login
pod_login

# Check if the last command executed properly
if [ $? -eq 0 ]; then
    echo "Logged in Successfully";
else
    echo "Login Failed";
fi


oc new-project cloud-pak-deployer
oc project cloud-pak-deployer
oc create serviceaccount cloud-pak-deployer-sa
oc adm policy add-scc-to-user privileged -z cloud-pak-deployer-sa
oc adm policy add-cluster-role-to-user cluster-admin -z cloud-pak-deployer-sa

oc apply -f deployment.yaml


waittime=0
while [ "$pod_status" != "True" ] && [ $waittime -lt 300 ];do
        sleep 5
        pod_status=$(oc get po --no-headers -l deployment=cloud-pak-deployer -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}')
        echo "Metadata pod ready: $pod_status"
        waittime=$((waittime+5))
    done


CONFIG_DIR=./cpd-config && mkdir -p $CONFIG_DIR/config
cp cpd-config.yaml $CONFIG_DIR/config
STATUS_DIR=./cpd-status && mkdir -p $STATUS_DIR


DEPLOYER_POD=$(oc get po --no-headers -l deployment=cloud-pak-deployer | head -1 | awk '{print $1}')
oc rsh $DEPLOYER_POD rm -rf /Data/cpd-config && oc cp $CONFIG_DIR $DEPLOYER_POD:/Data/cpd-config/


oc rsh $DEPLOYER_POD  /cloud-pak-deployer/cp-deploy.sh vault set -vs cp_entitlement_key -vsv "$ICR_KEY"

oc rsh $DEPLOYER_POD /cloud-pak-deployer/cp-deploy.sh vault set \
  -vs cpd-demo-oc-login -vsv "oc login --server=$SERVER --token=$API_TOKEN"

oc rsh $DEPLOYER_POD /cloud-pak-deployer/cp-deploy.sh vault list

# Run the deployer
oc rsh $DEPLOYER_POD /cloud-pak-deployer/cp-deploy.sh env apply -v 
