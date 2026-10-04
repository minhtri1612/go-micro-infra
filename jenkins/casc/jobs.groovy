folder('services') {
  displayName('services')
  description('Multibranch per service repo. Jenkinsfile from the service: Test only. main → handoff release/<name>.')
}

folder('release') {
  displayName('release')
  description('DevOps-owned. Pipeline from go-micro-infra/jenkins/release/Jenkinsfile. Checkout allowlist repo. Docker/GitOps creds live here, not GLOBAL.')
  properties {
    folderCredentialsProperty {
      domainCredentials {
        domainCredentials {
          domain {
            name('')
            description('')
          }
          credentials {
            usernamePassword {
              scope('GLOBAL')
              id('dockerhub-credentials')
              description('Docker Hub — release folder only')
              username(System.getenv('DOCKERHUB_USER') ?: '')
              password(System.getenv('DOCKERHUB_TOKEN') ?: '')
            }
            usernamePassword {
              scope('GLOBAL')
              id('github-gitops-write')
              description('GitHub PAT write GitOps — release folder only')
              username(System.getenv('GITHUB_USER') ?: '')
              password(System.getenv('GITHUB_PAT_WRITE') ?: System.getenv('GITHUB_PAT') ?: '')
            }
          }
        }
      }
    }
  }
}

def services = [
  [name: 'product',      repo: 'https://github.com/minhtri1612/go-micro-product.git'],
  [name: 'inventory',    repo: 'https://github.com/minhtri1612/go-micro-inventory.git'],
  [name: 'order',        repo: 'https://github.com/minhtri1612/go-micro-order.git'],
  [name: 'payment',      repo: 'https://github.com/minhtri1612/go-micro-payment.git'],
  [name: 'notification', repo: 'https://github.com/minhtri1612/go-micro-notification.git'],
  [name: 'client',       repo: 'https://github.com/minhtri1612/go-micro-client.git'],
]

services.each { svc ->
  def jobName = "services/${svc.name}"
  multibranchPipelineJob(jobName) {
    displayName(svc.name)
    description("Test ${svc.name}. Jenkinsfile from the service repo. main → trigger release/${svc.name}. No Docker/GitOps creds.")
    branchSources {
      git {
        id("go-micro-${svc.name}")
        remote(svc.repo)
        credentialsId('github-go-micro-pat')
        includes('*')
      }
    }
    factory {
      workflowBranchProjectFactory {
        scriptPath('Jenkinsfile')
      }
    }
    triggers {
      periodicFolderTrigger {
        interval('2m')
      }
    }
    orphanedItemStrategy {
      discardOldItems {
        daysToKeep(7)
        numToKeep(20)
      }
    }
  }

  pipelineJob("release/${svc.name}") {
    displayName(svc.name)
    description("Release ${svc.name}. Pipeline from go-micro-infra, not the service Jenkinsfile. EXPECTED_SERVICE=${svc.name}.")
    parameters {
      stringParam('EXPECTED_SERVICE', svc.name, 'DevOps-owned. Job DSL sets this; do not change.')
      choiceParam('TARGET_ENV', ['dev', 'prod'], 'dev = rebuild + bump env/dev. prod = GitOps PR; no rebuild.')
    }
    definition {
      cpsScm {
        scm {
          git {
            remote {
              url('https://github.com/minhtri1612/go-micro-infra.git')
              credentials('github-go-micro-pat')
            }
            branch('*/main')
          }
        }
        scriptPath('jenkins/release/Jenkinsfile')
        lightweight(false)
      }
    }
    properties {
      githubProjectUrl(svc.repo.replace('.git', '/'))
    }
  }
}

folder('platform') {
  displayName('platform')
  description('Admin only. Developers have no Discover/Read on this folder.')
}

pipelineJob('platform/terraform-management-plan') {
  description('Polls GitHub for open PRs to main (Jenkins is private; no webhook). Plans terraform/**. Sets check terraform-plan. No apply.')
  parameters {
    stringParam('GIT_REF', 'origin/main', 'Manual fallback SHA/ref if the poll did not pick a PR')
    stringParam('GH_PR_NUMBER', '', 'Manual PR number. Empty = newest open PR targeting main.')
  }
  triggers {
    cron('H/2 * * * *')
  }
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url('https://github.com/minhtri1612/go-micro-infra.git')
            credentials('github-go-micro-pat')
          }
          branch('*/main')
        }
      }
      scriptPath('jenkins/terraform/Jenkinsfile.plan')
      lightweight(false)
    }
  }
  properties {
    githubProjectUrl('https://github.com/minhtri1612/go-micro-infra/')
  }
}

pipelineJob('platform/terraform-management-apply') {
  description('SCM poll of main. Applies when terraform/** changed. Manual destroy-target still allowed.')
  parameters {
    choiceParam('ACTION', ['apply', 'destroy-target'], 'Poll/merge uses apply. destroy-target is manual only.')
    stringParam('TARGET', '', 'Unused. destroy-target is retired.')
    booleanParam('SKIP_PR_COMPARE', false, 'Emergency only. Default compares PR plan summary.')
    stringParam('PR_PLAN_SUMMARY', '', 'Override; else read PR comment marker')
  }
  triggers {
    scm('H/2 * * * *')
  }
  definition {
    cpsScm {
      scm {
        git {
          remote {
            url('https://github.com/minhtri1612/go-micro-infra.git')
            credentials('github-go-micro-pat')
          }
          branch('*/main')
        }
      }
      scriptPath('jenkins/terraform/Jenkinsfile.apply')
      lightweight(false)
    }
  }
  properties {
    githubProjectUrl('https://github.com/minhtri1612/go-micro-infra/')
  }
}
