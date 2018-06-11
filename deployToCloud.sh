#!/bin/bash


DEPLOYMENT_LOCATION=westeurope
BLOCKCHAIN_RESOURCE_GROUP=POC-Blockchain
BLACK_CONTAINER_REGISTRY_NAME=blackCR
BLOCKCHAIN_CLUSTER_NAME=blackCluster
BLOCKCHAIN_IMAGE_TAG=v1
ARCH=`uname -m`
BLOCKCHAIN_ADMIN_USERNAME=admin
BLOCKCHAIN_ADMIN_PASSWORD=adminpw



echo Checking your version of the Azure CLI
#az --version

# Do not let this proceed if they do not have Azure CLI v2.0.27 or higher





 # Create a Resource Group for all Blockchain components
if [ $(az group exists --resource-group $BLOCKCHAIN_RESOURCE_GROUP) = 'false' ]; then
    echo Created resource group $BLOCKCHAIN_RESOURCE_GROUP
    az group create --name $BLOCKCHAIN_RESOURCE_GROUP --location $DEPLOYMENT_LOCATION
fi

# Create a Container Registry for storing all the blockchain component images
if [ $(az acr check-name --name $BLACK_CONTAINER_REGISTRY_NAME --output table | grep -c True) = 1 ]; then
    echo Created container registry $BLACK_CONTAINER_REGISTRY_NAME
    az acr create --resource-group $BLOCKCHAIN_RESOURCE_GROUP --name $BLACK_CONTAINER_REGISTRY_NAME --sku Basic
fi

# Create a Kubernetes Cluster for starting and managing the Blockchain
if [ "$(az acs list)" = "[]" ]; then
    echo Created a Kubernetes Cluster : $BLOCKCHAIN_CLUSTER_NAME
    az acs create --orchestrator-type kubernetes --resource-group $BLOCKCHAIN_RESOURCE_GROUP --name $BLOCKCHAIN_CLUSTER_NAME --generate-ssh-keys
fi

# Install the Kubectl toolset if it is missing
if [ $(kubectl version 2>&1 | grep -c "Client Version") -eq 0 ]; then
    echo Installing the Kubernetes management toolset : Kubectl
    az acs kubernetes install-cli
fi


# Login to the Container Registry
echo Logging into container registry
az acr login --name $BLACK_CONTAINER_REGISTRY_NAME

# Get the login server name
CR_LOGIN_SERVER_NAME=$(az acr list --resource-group $BLOCKCHAIN_RESOURCE_GROUP --query "[].{acrLoginServer:loginServer}" --output table | tail --line 1)

# Function to check for an image in the Container Registry, and create it if missing
createBlockchainImageInCR() {
    if [ $(az acr repository show-tags --name $BLACK_CONTAINER_REGISTRY_NAME --repository fabric-$1 --output table | grep $BLOCKCHAIN_IMAGE_TAG -c) -eq 0 ]; then

        if [ $(docker images | grep $CR_LOGIN_SERVER_NAME/fabric-$1 | grep -c $BLOCKCHAIN_IMAGE_TAG) -eq 1 ]; then
            echo "docker rmi $CR_LOGIN_SERVER_NAME/fabric-$1:$BLOCKCHAIN_IMAGE_TAG"
        fi
        echo "docker tag hyperledger/fabric-$1 $CR_LOGIN_SERVER_NAME/fabric-$1:$BLOCKCHAIN_IMAGE_TAG"
        echo "docker push $CR_LOGIN_SERVER_NAME/fabric-$1:$BLOCKCHAIN_IMAGE_TAG"
    fi
}

# Prepare and push each blockchain component image to the Container Registry
createBlockchainImageInCR ca
createBlockchainImageInCR couchdb
createBlockchainImageInCR orderer
createBlockchainImageInCR peer
createBlockchainImageInCR ccenv


# Login to the Kubernetes Cluster
echo Logging into Kubernetes Cluster
az acs kubernetes get-credentials --resource-group $BLOCKCHAIN_RESOURCE_GROUP --name $BLOCKCHAIN_CLUSTER_NAME

# Convert the Docker-Compose file to Kubernetes
rm -rf ./config/kubernetes
mkdir ./config/kubernetes
cp ./config/docker-compose.yml ./config/kubernetes
cd ./config/kubernetes

sed -i 's/image: hyperledger/image: '"$CR_LOGIN_SERVER_NAME"'/g' docker-compose.yml
sed -i 's/$ARCH-1.0.4/'"$BLOCKCHAIN_IMAGE_TAG"'/g' docker-compose.yml
sed -i 's/.poc.black.insure:/-poc-black-insure:/g' docker-compose.yml
sed -i 's/.poc.black.insure$/-poc-black-insure/g' docker-compose.yml
sed -i 's/.black.insure:/-black-insure:/g' docker-compose.yml
sed -i 's/.black.insure$/-black-insure/g' docker-compose.yml




../../bin/kompose --file ./docker-compose.yml --verbose --provider kubernetes convert

# Create each PerisistentVolume Claim
for i in *claim*.yaml; do
    kubectl create -f "$i"
done

# Create each Deployment
for j in *deployment.yaml; do
    kubectl create -f "$j"
done

# Create each Service
for k in *service.yaml; do
    kubectl create -f "$k"
done