<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@1540.v295eccc9778c">
  <actions/>
  <description>__JOB_DESCRIPTION__</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>ACTION</name>
          <description>Container control</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>start</string>
              <string>stop</string>
              <string>restart</string>
              <string>build-and-start</string>
              <string>update-from-github</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        __EXTRA_PARAMS__
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
