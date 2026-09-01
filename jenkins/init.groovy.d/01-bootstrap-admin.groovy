import jenkins.model.*
import hudson.model.User
import hudson.security.*
import jenkins.install.*

def instance = Jenkins.getInstance()
def username = System.getenv('JENKINS_ADMIN_USER') ?: 'admin'
def password = System.getenv('JENKINS_ADMIN_PASS')

if (password == null || password.trim().isEmpty()) {
  println 'SKIP 01-bootstrap-admin: JENKINS_ADMIN_PASS not set'
  return
}

if (instance.getInstallState() != InstallState.INITIAL_SETUP_COMPLETED) {
  println 'Completing Jenkins initial setup (skip wizard)'
  def realm = new HudsonPrivateSecurityRealm(false)
  realm.createAccount(username, password)
  println "Created admin user: ${username}"
  instance.setSecurityRealm(realm)
  def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
  strategy.setAllowAnonymousRead(false)
  instance.setAuthorizationStrategy(strategy)
  instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
  instance.save()
  println 'Jenkins setup wizard skipped'
} else {
  def user = User.get(username, false)
  if (user == null) {
    def realm = instance.getSecurityRealm()
    if (realm instanceof HudsonPrivateSecurityRealm) {
      realm.createAccount(username, password)
      println "Created admin user: ${username}"
      instance.save()
    }
  }
}
