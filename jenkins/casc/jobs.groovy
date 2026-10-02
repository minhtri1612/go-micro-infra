folder('services') {
  displayName('services')
  description('Multibranch per service repo. main → image + bump env/dev.yaml. PR/other branches → image only.')
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
    description("CI ${svc.name}. Push main → image + bump env/dev.yaml. PR/other branches → image only.")
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
