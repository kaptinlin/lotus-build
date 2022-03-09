#!/bin/bash

rm -rf lotus
git clone https://github.com/filecoin-project/lotus.git
# cd lotus
# git pull
# git checkout v1.14.4

TAG=$(git rev-parse --short HEAD)
if docker pull kaptinlin/lotus:$TAG > /dev/null; then
  echo "Docker image of $TAG already exists, nothing to do."
  echo "Doing things anyway..."
  #exit 0
else
  echo "Building image..."
fi
TAG_VERSIONED=$(git describe --exact-match HEAD)

RUSTFLAGS="-C target-cpu=native" FFI_BUILD_FROM_SOURCE=1 make deps
cd ..

docker build -t kaptinlin/lotus:$TAG -t kaptinlin/lotus:latest --build-arg HTTP_PROXY=socks5://192.168.2.66:1080 --build-arg HTTPS_PROXY=socks5://192.168.2.66:1080 --network host .
docker login --username $DOCKER_USERNAME --password $DOCKER_PASSWORD
docker push kaptinlin/lotus:$TAG
docker push kaptinlin/lotus:latest

echo $TAG_VERSIONED
if [ -n "$TAG_VERSIONED" ]
then
  docker build -t kaptinlin/lotus:$TAG_VERSIONED .
  docker push kaptinlin/lotus:$TAG_VERSIONED
fi
