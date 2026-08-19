import jenkins.model.*
import hudson.security.*

def jenkins = Jenkins.getInstance()
def username = System.getenv('JENKINS_ADMIN_USER') ?: 'admin'
def password = System.getenv('JENKINS_ADMIN_PASS') ?: 'DevOps@2026'

def user = User.get(username, false)
if (user == null) {
  def realm = jenkins.getSecurityRealm()
  if (realm instanceof HudsonPrivateSecurityRealm) {
    realm.createAccount(username, password)
    println "Created Jenkins user: ${username}"
  }
} else {
  def details = user.getProperty(HudsonPrivateSecurityRealm.Details.class)
  if (details != null) {
    details.setPasswordHash(HudsonPrivateSecurityRealm.CONSOLE.encode(password))
    user.save()
    println "Reset Jenkins password for: ${username}"
  }
}
jenkins.save()
