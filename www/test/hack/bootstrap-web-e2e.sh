#!/bin/bash

# Copyright 2014 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to test web ui e2e tests using protractor works as expected.

set -o errexit
set -o nounset
set -o pipefail

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../../..
source "${KUBE_ROOT}/hack/lib/init.sh"

# The api version in which objects are currently stored in etcd.
KUBE_OLD_API_VERSION=${KUBE_OLD_API_VERSION:-"v1beta1"}
# The api version in which our etcd objects should be converted to.
# The new api version
KUBE_NEW_API_VERSION=${KUBE_NEW_API_VERSION:-"v1beta3"}

ETCD_HOST=${ETCD_HOST:-127.0.0.1}
ETCD_PORT=${ETCD_PORT:-4001}
API_PORT=${API_PORT:-8080}
API_HOST=${API_HOST:-127.0.0.1}
KUBELET_PORT=${KUBELET_PORT:-10250}
KUBE_API_VERSIONS=""
RUNTIME_CONFIG=""

KUBECTL="${KUBE_OUTPUT_HOSTBIN}/kubectl"
UPDATE_ETCD_OBJECTS_SCRIPT="${KUBE_ROOT}/cluster/update-storage-objects.sh"

function startApiServer() {
  kube::log::status "Starting kube-apiserver with KUBE_API_VERSIONS: ${KUBE_API_VERSIONS} and runtime_config: ${RUNTIME_CONFIG}"

  KUBE_API_VERSIONS="${KUBE_API_VERSIONS}" \
    "${KUBE_OUTPUT_HOSTBIN}/kube-apiserver" \
    --address="127.0.0.1" \
    --public_address_override="127.0.0.1" \
    --port="${API_PORT}" \
    --etcd_servers="http://${ETCD_HOST}:${ETCD_PORT}" \
    --public_address_override="127.0.0.1" \
    --kubelet_port=${KUBELET_PORT} \
    --runtime_config="${RUNTIME_CONFIG}" \
    --cert_dir="${TMPDIR:-/tmp/}" \
    --portal_net="10.0.0.0/24" 1>&2 &
  APISERVER_PID=$!

  kube::util::wait_for_url "http://127.0.0.1:${API_PORT}/healthz" "apiserver: "
}

function killApiServer() {
  kube::log::status "Killing api server"
  [[ -n ${APISERVER_PID-} ]] && kill ${APISERVER_PID} 1>&2 2>/dev/null
  unset APISERVER_PID
}

function cleanup() {
  killApiServer

  kube::etcd::cleanup

  kube::log::status "Clean up complete"
}

trap cleanup EXIT SIGINT

kube::etcd::start

kube::log::status "Running tests for web ui e2e scenario"

"${KUBE_ROOT}/hack/build-go.sh"

#######################################################
# Start a server which supports only the new api version.
#######################################################

KUBE_API_VERSIONS="${KUBE_NEW_API_VERSION}"
RUNTIME_CONFIG="api/all=false,api/${KUBE_NEW_API_VERSION}=true"
startApiServer

kube::log::status "Creating a pod"
${KUBECTL} create -f examples/pod.yaml

kube::log::status "Running e2e tests"

"protractor ${KUBE_ROOT}/www/master/protractor/conf.js --baseUrl http://localhost:8080/static/app/ --capabilities.browserName firefox"


