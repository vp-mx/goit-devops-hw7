# Rendered by jenkins.tf via templatefile() — do not edit directly, edit
# jenkins.tf / variables.tf instead. Kept as a real Helm values.yaml on disk
# (with placeholders) so its shape is easy to read; secrets are filled in at
# `terraform apply` time from Terraform variables, never committed as
# plaintext.
controller:
  admin:
    username: ${admin_username}
    password: ${admin_password}

  # NOTE: these are top-level controller.* fields per the actual jenkinsci/jenkins
  # chart schema (verified against the chart source) -- there is no nested
  # controller.service.* object; an earlier version of this file had one and
  # it was silently ignored (Helm doesn't validate unknown keys).
  serviceType: LoadBalancer
  servicePort: 80
  targetPort: 8080

  # Explicit heap size: the JVM's container-aware default sizing left too
  # little headroom during plugin loading (kubernetes, workflow-aggregator,
  # git, configuration-as-code, github, job-dsl all init at once on first
  # boot) and the controller got OOMKilled repeatedly. -Xmx must stay well
  # under resources.limits.memory to leave room for non-heap/metaspace/JVM
  # overhead.
  javaOpts: "-Xmx1024m -Xms512m"

  resources:
    requests:
      cpu: "${resources.requests.cpu}"
      memory: "${resources.requests.memory}"
    limits:
      cpu: "${resources.limits.cpu}"
      memory: "${resources.limits.memory}"

  installPlugins:
    - kubernetes:latest
    - workflow-aggregator:latest
    - git:latest
    - configuration-as-code:latest
    - credentials-binding:latest
    - github:latest
    - job-dsl:latest

  # JCasC: describes Jenkins' desired configuration as code, applied on
  # every controller start. This is what makes the seed job / GitHub
  # credentials reappear automatically even if the pod restarts and
  # persistence is disabled.
  JCasC:
    defaultConfig: true
    configScripts:
      credentials: |
        credentials:
          system:
            domainCredentials:
              - credentials:
                  - usernamePassword:
                      scope: GLOBAL
                      id: github-token
                      username: "${github_username}"
                      password: "${github_pat}"
                      description: GitHub PAT (repo read/write)
      pipeline-jobs: |
        # JCasC's own "jobs:" key IS the seeding mechanism -- it runs this
        # Job DSL script directly at controller boot/reload, fully trusted,
        # no Script Approval involved. No separate "seed-job" freestyle job
        # or nested "Process Job DSLs" build step needed (an earlier version
        # of this file used that pattern and hit two problems: the nested
        # dsl-step runs unsandboxed and needs manual approval, and it's a
        # different Groovy DSL context where sandbox(true) isn't even a
        # valid method -- calling it crashed Jenkins at boot entirely).
        jobs:
          - script: >
              pipelineJob("django-app-pipeline") {
                description("Kaniko build+push to ECR, then bump charts/django-app/values.yaml#image.tag -- see Jenkinsfile")
                parameters {
                  stringParam("ECR_REPOSITORY", "${ecr_repository_url}", "ECR repository URL (from terraform output ecr_repository_url)")
                  stringParam("TARGET_BRANCH", "${git_branch}", "Branch to push the updated chart tag to")
                }
                definition {
                  cpsScm {
                    scm {
                      git {
                        remote {
                          url("${git_repo_url}")
                          credentials("github-token")
                        }
                        branches("*/${git_branch}")
                      }
                    }
                    scriptPath("Jenkinsfile")
                  }
                }
              }

persistence:
  enabled: ${persistence_enabled}
%{ if persistence_enabled ~}
  storageClass: "ebs-sc"
  size: "5Gi"
%{ endif ~}

# Created out-of-band by Terraform (kubernetes_service_account.jenkins_sa)
# and bound to an IAM role via IRSA, so the Kaniko build pod can push to
# ECR without static AWS credentials.
serviceAccount:
  create: false
  name: jenkins-sa
