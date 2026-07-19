// CI/CD pipeline for the Django app (theme 8-9).
//
// Two stages:
//   1. Build the app/Dockerfile image with Kaniko (no docker daemon needed
//      inside the cluster) and push it to ECR.
//   2. Bump charts/django-app/values.yaml#image.tag to the new tag and push
//      the change back to this same repo. Argo CD (module.argo_cd) watches
//      that exact path/branch and re-syncs the cluster automatically — this
//      commit is the handoff between Jenkins (CI) and Argo CD (CD).
//
// Runs as a Kubernetes pod agent with two containers: `kaniko` (the build)
// and `git` (the tag bump + push). Both share the same workspace, which
// Jenkins already populated via its default `checkout scm` before any
// stage runs — no separate git clone needed.
//
// jenkins-sa (bound to an IAM role via IRSA, see modules/jenkins) is what
// lets the kaniko container push to ECR without any static AWS credentials.
pipeline {
  agent {
    kubernetes {
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    some-label: jenkins-kaniko
spec:
  serviceAccountName: jenkins-sa
  containers:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:v1.16.0-debug
      imagePullPolicy: Always
      command:
        - sleep
      args:
        - 99d
    - name: git
      image: alpine/git:2.45.2
      command:
        - sleep
      args:
        - 99d
"""
    }
  }

  parameters {
    // Defaults are wired in automatically by the seed job (see
    // modules/jenkins/values.yaml.tpl), which fills them in from Terraform
    // outputs — nothing to hardcode here.
    string(name: 'ECR_REPOSITORY', defaultValue: '', description: 'Full ECR repository URL (terraform output ecr_repository_url)')
    string(name: 'TARGET_BRANCH', defaultValue: 'main', description: 'Branch to push the updated chart tag to (must match what Argo CD tracks)')
  }

  environment {
    IMAGE_TAG    = "v1.0.${BUILD_NUMBER}"
    COMMIT_EMAIL = "jenkins-ci@localhost"
    COMMIT_NAME  = "jenkins-ci"
  }

  stages {
    stage('Sanity check') {
      steps {
        script {
          if (!params.ECR_REPOSITORY?.trim()) {
            error("ECR_REPOSITORY is empty — this job should have been created by the seed-job with a default value. Check modules/jenkins/values.yaml.tpl / re-run the seed-job.")
          }
        }
      }
    }

    stage('Build & Push Docker Image') {
      steps {
        container('kaniko') {
          sh '''
            /kaniko/executor \
              --context `pwd`/app \
              --dockerfile `pwd`/app/Dockerfile \
              --destination=${ECR_REPOSITORY}:${IMAGE_TAG} \
              --destination=${ECR_REPOSITORY}:latest \
              --cache=true \
              --insecure \
              --skip-tls-verify
          '''
        }
      }
    }

    stage('Update Chart Tag in Git') {
      steps {
        container('git') {
          withCredentials([usernamePassword(credentialsId: 'github-token', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PAT')]) {
            sh '''
              set -eu

              echo "PWD: $(pwd)"
              if [ -d .git ]; then
                echo ".git present"
              else
                echo ".git MISSING -- listing workspace root:"
                ls -la
              fi

              # The checkout happened in a different container of this same
              # pod (workspace is shared via the same emptyDir volume, but
              # git refuses to touch a repo it thinks it doesn't own across
              # that boundary) -- mark it safe rather than fighting UID
              # mismatches between containers.
              git config --global --add safe.directory "$(pwd)"

              sed -i "s/^  tag: .*/  tag: ${IMAGE_TAG}/" charts/django-app/values.yaml
              grep -q "tag: ${IMAGE_TAG}" charts/django-app/values.yaml

              git config user.email "$COMMIT_EMAIL"
              git config user.name "$COMMIT_NAME"

              # Re-inject credentials into whatever remote URL Jenkins already
              # checked this repo out from, so the push works regardless of
              # which repo/fork this pipeline runs against.
              ORIGIN_URL=$(git remote get-url origin)
              AUTHED_URL=$(echo "$ORIGIN_URL" | sed -E "s#https://([^@/]*@)?#https://${GIT_USERNAME}:${GIT_PAT}@#")
              git remote set-url origin "$AUTHED_URL"

              git add charts/django-app/values.yaml
              git commit -m "ci: update django-app image tag to ${IMAGE_TAG} (build #${BUILD_NUMBER})"
              git push origin "HEAD:${TARGET_BRANCH}"
            '''
          }
        }
      }
    }
  }

  post {
    success {
      echo "Pushed ${IMAGE_TAG} to ${params.ECR_REPOSITORY} and updated charts/django-app/values.yaml on ${params.TARGET_BRANCH}. Argo CD should pick it up within a few minutes (or on next manual sync)."
    }
  }
}
