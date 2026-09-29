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
  def parts = svc.repo.replaceFirst(/\.git$/, '').tokenize('/')
  def owner = parts[-2]
  def repoName = parts[-1]
  def jobName = "services/${svc.name}"
  try {
    multibranchPipelineJob(jobName) {
      displayName(svc.name)
      description("Multibranch CI ${svc.name}. Dev: Jenkinsfile. DevOps: go-micro-ci. CD: Argo.")
      branchSources {
        branchSource {
          source {
            github {
              id("go-micro-${svc.name}")
              repoOwner(owner)
              repository(repoName)
              credentialsId('github-go-micro-pat')
              traits {
                gitHubBranchDiscovery {
                  strategyId(1)
                }
                gitHubPullRequestDiscovery {
                  strategyId(2)
                }
              }
            }
          }
        }
      }
      factory {
        workflowBranchProjectFactory {
          scriptPath('Jenkinsfile')
        }
      }
      orphanedItemStrategy {
        discardOldItems {
          daysToKeep(7)
          numToKeep(20)
        }
      }
    }
  } catch (Exception e) {
    println "WARN skip ${jobName}: ${e.class.name}: ${e.message}"
  }
}

folder('platform') {
  displayName('platform')
  description('DevOps only. Terraform plan/apply/destroy-target. Dev không chạy folder này.')
}

pipelineJob('platform/terraform-management-plan') {
  description('Auto: GitHub pull_request (opened/synchronize). Plans terraform/** only. Sets check terraform-plan. No apply.')
  parameters {
    stringParam('GIT_REF', 'origin/main', 'Manual fallback if webhook did not set GIT_SHA')
    stringParam('GH_PR_NUMBER', '', 'Manual PR number')
  }
  triggers {
    genericTrigger {
      genericVariables {
        genericVariable {
          key('PR_ACTION')
          value('$.action')
          expressionType('JSONPath')
        }
        genericVariable {
          key('PR_NUMBER')
          value('$.pull_request.number')
          expressionType('JSONPath')
        }
        genericVariable {
          key('GIT_SHA')
          value('$.pull_request.head.sha')
          expressionType('JSONPath')
        }
        genericVariable {
          key('PR_BASE')
          value('$.pull_request.base.ref')
          expressionType('JSONPath')
        }
      }
      token(System.getenv('TF_PLAN_WEBHOOK_TOKEN') ?: 'unset')
      causeString('GitHub PR $PR_NUMBER $PR_ACTION')
      printContributedVariables(true)
      printPostContent(false)
      regexpFilterText('$PR_ACTION $PR_BASE')
      regexpFilterExpression('^(opened|synchronize|reopened|ready_for_review) main$')
    }
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
  description('Auto: GitHub push to main when terraform/** changed. Manual destroy-target still allowed.')
  parameters {
    choiceParam('ACTION', ['apply', 'destroy-target'], 'Webhook merge uses apply. destroy-target needs TARGET.')
    stringParam('TARGET', '', 'module.kind_host when ACTION=destroy-target')
    booleanParam('SKIP_PR_COMPARE', false, 'Emergency only. Default compares PR plan summary.')
    stringParam('PR_PLAN_SUMMARY', '', 'Override; else read PR comment marker')
  }
  triggers {
    genericTrigger {
      genericVariables {
        genericVariable {
          key('PUSH_REF')
          value('$.ref')
          expressionType('JSONPath')
        }
        genericVariable {
          key('PUSH_DELETED')
          value('$.deleted')
          expressionType('JSONPath')
        }
        genericVariable {
          key('PUSH_AFTER')
          value('$.after')
          expressionType('JSONPath')
        }
      }
      token(System.getenv('TF_APPLY_WEBHOOK_TOKEN') ?: 'unset')
      causeString('GitHub push $PUSH_REF')
      printContributedVariables(true)
      printPostContent(false)
      regexpFilterText('$PUSH_REF $PUSH_DELETED')
      regexpFilterExpression('^refs/heads/main false$')
    }
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
