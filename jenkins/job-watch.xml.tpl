<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@1540.v295eccc9778c">
  <actions/>
  <description>__JOB_DESCRIPTION__</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>__PIPELINE_SCRIPT__</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
