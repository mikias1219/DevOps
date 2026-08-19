<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@1540.v295eccc9778c">
  <actions/>
  <description>__JOB_DESCRIPTION__</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>REPO</name>
          <description>Which GitHub repo the watcher should follow</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>collaboration-backend</string>
              <string>collaboration-frontend</string>
              <string>collaboration-both</string>
              <string>housekeeper-backend</string>
              <string>housekeeper-frontend</string>
              <string>housekeeper-both</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>REBUILD_NOW</name>
          <description>After switching, pull that branch and recreate the container</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>__PIPELINE_SCRIPT__</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
