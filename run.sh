#!/bin/bash

# rm -rf lotus
git clone https://github.com/filecoin-project/lotus.git
cd lotus
# # git pull
git checkout v1.20.0

echo "Building image..."

# RUSTFLAGS="-C target-cpu=native" FFI_BUILD_FROM_SOURCE=1 make deps
cd ..

docker build -t kaptinlin/lotus:latest --network host .
# docker login --username $DOCKER_USERNAME --password $DOCKER_PASSWORD
# docker push kaptinlin/lotus:latest
