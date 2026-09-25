folder('services') {
  displayName('services')
  description('Góc nhìn Dev: mỗi repo một job. Push code → job của service đó. Logic CI ở library go-micro-ci (DevOps).')
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
  pipelineJob("services/${svc.name}") {
    description("CI ${svc.name}. Dev sở hữu Jenkinsfile trong repo. DevOps sở hữu go-micro-ci.")
    definition {
      cpsScm {
        scm {
          git {
            remote {
              url(svc.repo)
              credentials('github-go-micro-pat')
            }
            branch('*/main')
          }
        }
        scriptPath('Jenkinsfile')
        lightweight(true)
      }
    }
    properties {
      githubProjectUrl(svc.repo.replace('.git', '/'))
    }
    triggers {
      githubPush()
    }
  }
}

folder('platform') {
  displayName('platform')
  description('DevOps only. Terraform plan/apply/destroy-target. Dev không chạy folder này.')
}

pipelineJob('platform/terraform-management-plan') {
  description('Plan management stack. Jenkinsfile from main; workspace then checks out GIT_REF. No apply.')
  parameters {
    stringParam('GIT_REF', 'origin/main', 'Branch/SHA to plan')
    stringParam('GH_PR_NUMBER', '', 'Optional PR number to comment')
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
  description('Apply or destroy-target on origin/main only. Never full-stack destroy (would kill Jenkins). destroy-target allowlist: module.kind_host.')
  parameters {
    choiceParam('ACTION', ['apply', 'destroy-target'], 'apply = plan -out then apply tfplan. destroy-target needs TARGET.')
    stringParam('TARGET', '', 'module.kind_host when ACTION=destroy-target')
    booleanParam('SKIP_PR_COMPARE', true, 'Lab default: skip PR plan count compare')
    stringParam('PR_PLAN_SUMMARY', '', 'add=N change=N destroy=N when SKIP_PR_COMPARE=false')
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
