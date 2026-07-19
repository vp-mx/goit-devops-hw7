#!/usr/bin/env bash
# Build the theme-4 Django image and push it to ECR.
#
# Usage:
#   ./scripts/push-to-ecr.sh [REGION] [REPO_NAME] [IMAGE_TAG] [APP_DIR]
#
# Defaults: REGION=eu-north-1  REPO_NAME=lesson-7-ecr  IMAGE_TAG=latest
#           APP_DIR=../../goit-devops-hw (the theme-4 Django project, a
#           sibling of this repo — adjust if your layout differs).
#
# The account id and registry host are resolved automatically from the active
# AWS credentials, so anyone can run this against their own account without
# editing anything. Requires: aws CLI, docker.
set -euo pipefail

REGION="${1:-eu-north-1}"
REPO_NAME="${2:-lesson-7-ecr}"
IMAGE_TAG="${3:-latest}"

# Directory of this script, so it works regardless of the current working dir.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${4:-${SCRIPT_DIR}/../../../goit-devops-hw}"

if [ ! -f "${APP_DIR}/Dockerfile" ]; then
  echo "!! No Dockerfile found in ${APP_DIR}"
  echo "   Pass the theme-4 Django project directory as the 4th argument, e.g.:"
  echo "   ./scripts/push-to-ecr.sh ${REGION} ${REPO_NAME} ${IMAGE_TAG} /path/to/goit-devops-hw"
  exit 1
fi

echo ">> Resolving AWS account..."
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"

echo ">> Account:  ${ACCOUNT_ID}"
echo ">> Region:   ${REGION}"
echo ">> App dir:  ${APP_DIR}"
echo ">> Image:    ${IMAGE_URI}"

echo ">> Logging Docker in to ECR..."
aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

# Build for linux/amd64 so the image runs on the EKS x86_64 nodes even when
# built on an Apple Silicon (arm64) laptop.
echo ">> Building image (linux/amd64)..."
docker build --platform linux/amd64 -t "${IMAGE_URI}" "${APP_DIR}"

echo ">> Pushing image..."
docker push "${IMAGE_URI}"

echo ""
echo ">> Done. Use this image in Helm:"
echo "   helm upgrade --install django-app charts/django-app --set image.repository=${REGISTRY}/${REPO_NAME} --set image.tag=${IMAGE_TAG}"
