import jenkins.model.*
import hudson.security.*

def jenkins = Jenkins.getInstance()

// Prefer env from compose env_file (jenkins/secrets/admin.env). No hardcoded password.
def username = System.getenv('JENKINS_ADMIN_USER') ?: 'admin'
def password = System.getenv('JENKINS_ADMIN_PASS')

if (password == null || password.trim().isEmpty()) {
  println "SKIP reset-admin: JENKINS_ADMIN_PASS not set (mount jenkins/secrets/admin.env)"
  return
}

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
