#!/bin/bash


ARCH=`uname -m`
BLOCKCHAIN_ADMIN_USERNAME=admin
BLOCKCHAIN_ADMIN_PASSWORD=adminpw


# Clear out any previous deployments
rm -rf ./bin
rm -rf ./config/crypto-config
rm -f ./config/composer-channel.tx
rm -f ./config/composer-genensis.block
rm -rf ./config/kubernetes

# Download the Hyperledger Fabric network build tools
curl -sSL https://goo.gl/kFFqh5 | bash -s 1.0.4

# Download the Kompose conversion tool for creating Kubernetes files from Docker-Compose
curl -L https://github.com/kubernetes/kompose/releases/download/v1.13.0/kompose-linux-amd64 -o ./bin/kompose
chmod +x ./bin/kompose

# Create the crypto material and genesis block for the Fabric network
cd config
../bin/cryptogen generate --config=./crypto-config.yaml
export FABRIC_CFG_PATH=$PWD
../bin/configtxgen -profile ComposerOrdererGenesis -outputBlock ./composer-genesis.block
../bin/configtxgen -profile ComposerChannel -outputCreateChannelTx ./composer-channel.tx -channelID composerchannel
mkdir crypto-config/peerOrganizations/poc.black.insure/channel
cd ..

# Update the CA signing key in the Docker Compose configuration
CA_SIGNING_KEY=$(ls config/crypto-config/peerOrganizations/poc.black.insure/ca | grep _sk)
sed -i 's/[a-z0-9]*_sk/'"$CA_SIGNING_KEY"'/g' config/docker-compose.yml

# Start the Network locally
ARCH=$ARCH ADMIN_USERNAME=$BLOCKCHAIN_ADMIN_USERNAME ADMIN_PASSWORD=$BLOCKCHAIN_ADMIN_PASSWORD docker-compose -f ./config/docker-compose.yml down
docker-compose rm
ARCH=$ARCH ADMIN_USERNAME=$BLOCKCHAIN_ADMIN_USERNAME ADMIN_PASSWORD=$BLOCKCHAIN_ADMIN_PASSWORD docker-compose -f ./config/docker-compose.yml up -d

# Wait for startup to complete
sleep 25

# Create the main channel and join all the peers to it
docker exec peer0.poc.black.insure peer channel create -o orderer.black.insure:7050 -c composerchannel -f /etc/hyperledger/configtx/composer-channel.tx
docker exec peer0.poc.black.insure mv composerchannel.block /etc/hyperledger/channel/composerchannel.block
docker exec -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/msp/users/Admin@poc.black.insure/msp" peer0.poc.black.insure peer channel join -b /etc/hyperledger/channel/composerchannel.block
docker exec -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/msp/users/Admin@poc.black.insure/msp" peer1.poc.black.insure peer channel join -b /etc/hyperledger/channel/composerchannel.block
docker exec -e "CORE_PEER_MSPCONFIGPATH=/etc/hyperledger/msp/users/Admin@poc.black.insure/msp" peer2.poc.black.insure peer channel join -b /etc/hyperledger/channel/composerchannel.block
