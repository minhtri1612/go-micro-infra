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
