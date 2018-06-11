#!/bin/bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Grab the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z "${HL_COMPOSER_CLI}" ]; then
  HL_COMPOSER_CLI=$(which composer)
fi

echo
# check that the composer command exists at a version >v0.14
COMPOSER_VERSION=$("${HL_COMPOSER_CLI}" --version 2>/dev/null)
COMPOSER_RC=$?

if [ $COMPOSER_RC -eq 0 ]; then
    AWKRET=$(echo $COMPOSER_VERSION | awk -F. '{if ($2<15 || $2>16) print "1"; else print "0";}')
    if [ $AWKRET -eq 1 ]; then
        echo $COMPOSER_VERSION is not supported for this level of fabric. Please use version 0.16
        exit 1
    else
        echo Using composer-cli at $COMPOSER_VERSION
    fi
else
    echo 'Need to have composer-cli installed at version 0.16'
    exit 1
fi

cat << EOF > /tmp/.connection.json
{
    "name": "hlfv1",
    "type": "hlfv1",
    "orderers": [
       { "url" : "grpc://localhost:7050" }
    ],
    "ca": { "url": "http://localhost:7054", "name": "ca.poc.black.insure"},
    "peers": [
        {
            "requestURL": "grpc://localhost:7051",
            "eventURL": "grpc://localhost:7053"
        },
        {
            "requestURL": "grpc://localhost:8051",
            "eventURL": "grpc://localhost:8053"
        },
        {
            "requestURL": "grpc://localhost:9051",
            "eventURL": "grpc://localhost:9053"
        }
    ],
    "channel": "composerchannel",
    "mspID": "POCMSP",
    "timeout": 300
}
EOF

# Get the Admin Signing Key and Cert
ADMIN_SIGNING_KEY=$(ls config/crypto-config/peerOrganizations/poc.black.insure/users/Admin@poc.black.insure/msp/keystore | grep _sk)
PRIVATE_KEY="${DIR}"/config/crypto-config/peerOrganizations/poc.black.insure/users/Admin@poc.black.insure/msp/keystore/$ADMIN_SIGNING_KEY
CERT="${DIR}"/config/crypto-config/peerOrganizations/poc.black.insure/users/Admin@poc.black.insure/msp/signcerts/Admin@poc.black.insure-cert.pem

if "${HL_COMPOSER_CLI}" card list -n PeerAdmin@hlfv1 > /dev/null; then
    "${HL_COMPOSER_CLI}" card delete -n PeerAdmin@hlfv1
fi
"${HL_COMPOSER_CLI}" card create -p /tmp/.connection.json -u PeerAdmin -c "${CERT}" -k "${PRIVATE_KEY}" -r PeerAdmin -r ChannelAdmin --file /tmp/PeerAdmin@hlfv1.card
"${HL_COMPOSER_CLI}" card import --file /tmp/PeerAdmin@hlfv1.card 

rm -rf /tmp/.connection.json

echo "Hyperledger Composer PeerAdmin card has been imported"
"${HL_COMPOSER_CLI}" card list

