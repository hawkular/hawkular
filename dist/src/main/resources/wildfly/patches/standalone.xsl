<?xml version="1.0" encoding="UTF-8"?>
<!--

    Copyright 2015 Red Hat, Inc. and/or its affiliates
    and other contributors as indicated by the @author tags.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

-->

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xalan="http://xml.apache.org/xalan"
                xmlns:ds="urn:jboss:domain:datasources:2.0"
                xmlns:ra="urn:jboss:domain:resource-adapters:2.0"
                xmlns:ejb3="urn:jboss:domain:ejb3:2.0"
                version="2.0"
                exclude-result-prefixes="xalan ds ra ejb3">

  <!-- will indicate if this is a "dev" build or "production" build -->
  <xsl:param name="kettle.build.type"/>
  <xsl:param name="uuid.hawkular.accounts.backend"/>

  <xsl:output method="xml" version="1.0" encoding="UTF-8" indent="yes" xalan:indent-amount="4" standalone="no"/>
  <xsl:strip-space elements="*"/>

  <!-- enable/disable deployment scanner -->
  <xsl:template name="deployment-scanner">
    <xsl:if test="$kettle.build.type='dev'">
      <xsl:attribute name="scan-enabled">true</xsl:attribute>
    </xsl:if>
    <xsl:if test="$kettle.build.type='production'">
      <xsl:attribute name="scan-enabled">false</xsl:attribute>
    </xsl:if>
  </xsl:template>

  <xsl:template match="node()[name(.)='deployment-scanner']">
    <xsl:copy>
      <xsl:call-template name="deployment-scanner"/>
      <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
  </xsl:template>

  <!-- add some logger categories -->
  <xsl:template name="loggers">
    <xsl:if test="$kettle.build.type='dev'">
      <logger category="org.hawkular">
        <level name="DEBUG"/>
      </logger>
      <logger category="org.hawkular.bus">
        <level name="DEBUG"/>
      </logger>
      <logger category="org.hawkular.nest">
        <level name="DEBUG"/>
      </logger>
    </xsl:if>
    <xsl:if test="$kettle.build.type='production'">
      <logger category="org.hawkular">
        <level name="INFO"/>
      </logger>
      <logger category="org.hawkular.bus">
        <level name="INFO"/>
      </logger>
      <logger category="org.hawkular.nest">
        <level name="INFO"/>
      </logger>
    </xsl:if>
  </xsl:template>

  <xsl:template match="node()[name(.)='periodic-rotating-file-handler']">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
    <xsl:call-template name="loggers"/>
  </xsl:template>

  <!-- add bus resource adapter -->
  <xsl:template name="resource-adapters">
    <resource-adapters>
      <resource-adapter id="activemq-rar">
        <module slot="main" id="org.apache.activemq.ra" />
        <transaction-support>XATransaction</transaction-support>
        <config-property name="UseInboundSession">false</config-property>
        <xsl:comment><![CDATA[
          <config-property name="Password">
            defaultPassword
          </config-property>
          <config-property name="UserName">
            defaultUser
          </config-property>
        ]]></xsl:comment>
        <config-property name="ServerUrl">vm://org.hawkular.bus.broker.${jboss.node.name}?create=false</config-property>
        <connection-definitions>
          <connection-definition class-name="org.apache.activemq.ra.ActiveMQManagedConnectionFactory"
                                 jndi-name="java:/HawkularBusConnectionFactory"
                                 enabled="true"
                                 use-java-context="true"
                                 pool-name="HawkularBusConnectionFactory">
            <xa-pool>
              <min-pool-size>1</min-pool-size>
              <max-pool-size>20</max-pool-size>
              <prefill>false</prefill>
              <is-same-rm-override>false</is-same-rm-override>
            </xa-pool>
          </connection-definition>
        </connection-definitions>
        <admin-objects>
          <admin-object use-java-context="true" enabled="true" class-name="org.apache.activemq.command.ActiveMQTopic" jndi-name="java:/topic/HawkularInventoryChanges" pool-name="HawkularInventoryChanges">
             <config-property name="PhysicalName">HawkularInventoryChanges</config-property>
          </admin-object>
          <admin-object use-java-context="true" enabled="true" class-name="org.apache.activemq.command.ActiveMQTopic" jndi-name="java:/topic/HawkularMetricData" pool-name="HawkularMetricData">
             <config-property name="PhysicalName">HawkularMetricData</config-property>
          </admin-object>
          <admin-object use-java-context="true" enabled="true" class-name="org.apache.activemq.command.ActiveMQTopic" jndi-name="java:/topic/HawkularAvailData" pool-name="HawkularAvailData">
             <config-property name="PhysicalName">HawkularAvailData</config-property>
          </admin-object>
        </admin-objects>
      </resource-adapter>
    </resource-adapters>
  </xsl:template>

  <xsl:template match="ra:subsystem">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
      <xsl:call-template name="resource-adapters"/>
    </xsl:copy>
  </xsl:template>

  <!-- add MDB definition -->
  <xsl:template name="mdb">
    <mdb>
      <resource-adapter-ref resource-adapter-name="activemq-rar"/>
      <bean-instance-pool-ref pool-name="mdb-strict-max-pool"/>
    </mdb>
  </xsl:template>

  <xsl:template match="ejb3:subsystem">
    <xsl:copy>
      <xsl:call-template name="mdb"/>
      <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
  </xsl:template>

  <!-- Remove the out-of-box datasource example and add our own datasource -->
  <xsl:template name="datasources">
    <datasources>
      <datasource jta="true" jndi-name="java:jboss/datasources/HawkularDS" pool-name="HawkularDS" enabled="true" use-ccm="true">
        <connection-url>jdbc:h2:${jboss.server.data.dir}/hawkular_db;MVCC=TRUE</connection-url>
        <driver-class>org.h2.Driver</driver-class>
        <driver>h2</driver>
        <security>
          <user-name>sa</user-name>
          <password>sa</password>
        </security>
        <validation>
          <validate-on-match>false</validate-on-match>
          <background-validation>false</background-validation>
        </validation>
        <timeout>
          <set-tx-query-timeout>false</set-tx-query-timeout>
          <blocking-timeout-millis>0</blocking-timeout-millis>
          <idle-timeout-minutes>0</idle-timeout-minutes>
          <query-timeout>0</query-timeout>
          <use-try-lock>0</use-try-lock>
          <allocation-retry>0</allocation-retry>
          <allocation-retry-wait-millis>0</allocation-retry-wait-millis>
        </timeout>
        <statement>
          <share-prepared-statements>false</share-prepared-statements>
        </statement>
      </datasource>
      <datasource jndi-name="java:jboss/datasources/KeycloakDS" pool-name="KeycloakDS" enabled="true" use-java-context="true">
        <connection-url>jdbc:h2:${jboss.server.data.dir}${/}h2${/}keycloak;AUTO_SERVER=TRUE</connection-url>
        <driver>h2</driver>
        <security>
          <user-name>sa</user-name>
          <password>sa</password>
        </security>
      </datasource>
      <drivers>
        <driver name="h2" module="com.h2database.h2">
          <xa-datasource-class>org.h2.jdbcx.JdbcDataSource</xa-datasource-class>
        </driver>
      </drivers>
    </datasources>
  </xsl:template>

  <xsl:template match="ds:datasources">
    <xsl:call-template name="datasources" />
  </xsl:template>

  <xsl:template match="@datasource[.='java:jboss/datasources/ExampleDS']">
    <xsl:attribute name="datasource">java:jboss/datasources/HawkularDS</xsl:attribute>
  </xsl:template>

  <!-- Tweak EE bindings -->
  <xsl:template match="@jms-connection-factory[.='java:jboss/DefaultJMSConnectionFactory']">
    <xsl:attribute name="jms-connection-factory">java:/HawkularBusConnectionFactory</xsl:attribute>
  </xsl:template>

  <!-- add system properties -->
  <xsl:template name="system-properties">
    <system-properties>
      <property name="hawkular-metrics.backend" value="embedded_cass" />
    </system-properties>
  </xsl:template>

  <!-- add additional subsystem extensions -->
  <xsl:template match="node()[name(.)='extensions']">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
      <extension module="org.keycloak.keycloak-subsystem"/>
      <extension module="org.hawkular.agent.monitor"/>
    </xsl:copy>
    <xsl:call-template name="system-properties"/>
  </xsl:template>

  <!-- add extension subsystem configurations -->
  <xsl:template match="node()[name(.)='profile']">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>

      <!-- Hawkular Monitor agent subsystem -->
      <subsystem xmlns="urn:org.hawkular.agent.monitor:monitor:1.0"
                 enabled="true"
                 apiJndiName="java:global/hawkular/agent/monitor/api"
                 numMetricSchedulerThreads="3"
                 numAvailSchedulerThreads="3">

        <diagnostics enabled="true"
                     reportTo="LOG"
                     interval="1"
                     timeUnits="minutes"/>

        <storage-adapter type="HAWKULAR"
                         username="jdoe"
                         password="password">
                         <xsl:attribute name="url">http://${jboss.bind.address:127.0.0.1}:${jboss.http.port:8080}</xsl:attribute>
        </storage-adapter>

        <metric-set-dmr name="WildFly Memory Metrics" enabled="true">
          <metric-dmr name="Heap Used"
                      interval="30"
                      timeUnits="seconds"
                      metricUnits="bytes"
                      path="/core-service=platform-mbean/type=memory"
                      attribute="heap-memory-usage#used" />
          <metric-dmr name="Heap Committed"
                      interval="1"
                      timeUnits="minutes"
                      path="/core-service=platform-mbean/type=memory"
                      attribute="heap-memory-usage#committed" />
          <metric-dmr name="NonHeap Used"
                      interval="30"
                      timeUnits="seconds"
                      path="/core-service=platform-mbean/type=memory"
                      attribute="non-heap-memory-usage#used" />
          <metric-dmr name="NonHeap Committed"
                      interval="1"
                      timeUnits="minutes"
                      path="/core-service=platform-mbean/type=memory"
                      attribute="non-heap-memory-usage#committed" />
        </metric-set-dmr>

        <metric-set-dmr name="WildFly Threading Metrics" enabled="true">
          <metric-dmr name="Thread Count"
                      interval="2"
                      timeUnits="minutes"
                      metricUnits="none"
                      path="/core-service=platform-mbean/type=threading"
                      attribute="thread-count" />
        </metric-set-dmr>

        <metric-set-dmr name="Undertow Metrics" enabled="true">
          <metric-dmr name="Active Sessions"
                      interval="2"
                      timeUnits="minutes"
                      path="/subsystem=undertow"
                      attribute="active-sessions" />
          <metric-dmr name="Sessions Created"
                      interval="2"
                      timeUnits="minutes"
                      path="/subsystem=undertow"
                      attribute="sessions-created" />
        </metric-set-dmr>

        <metric-set-dmr name="Servlet Metrics" enabled="true">
          <metric-dmr name="Max Request Time"
                      interval="5"
                      timeUnits="minutes"
                      metricUnits="milliseconds"
                      path="/"
                      attribute="max-request-time" />
          <metric-dmr name="Min Request Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="min-request-time" />
          <metric-dmr name="Total Request Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="total-request-time" />
          <metric-dmr name="Request Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="request-count" />
        </metric-set-dmr>

        <metric-set-dmr name="Singleton EJB Metrics" enabled="true">
          <metric-dmr name="Execution Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="execution-time" />
          <metric-dmr name="Invocations"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="invocations" />
          <metric-dmr name="Peak Concurrent Invocations"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="peak-concurrent-invocations" />
          <metric-dmr name="Wait Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="wait-time" />
        </metric-set-dmr>

        <metric-set-dmr name="Message Driven EJB Metrics" enabled="true">
          <metric-dmr name="Execution Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="execution-time" />
          <metric-dmr name="Invocations"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="invocations" />
          <metric-dmr name="Peak Concurrent Invocations"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="peak-concurrent-invocations" />
          <metric-dmr name="Wait Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="wait-time" />
          <metric-dmr name="Pool Availabile Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-available-count" />
          <metric-dmr name="Pool Create Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-create-count" />
          <metric-dmr name="Pool Current Size"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-current-size" />
          <metric-dmr name="Pool Max Size"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-max-size" />
          <metric-dmr name="Pool Remove Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-remove-count" />
        </metric-set-dmr>

        <metric-set-dmr name="Stateless Session EJB Metrics" enabled="true">
          <metric-dmr name="Execution Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="execution-time" />
          <metric-dmr name="Invocations"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="invocations" />
          <metric-dmr name="Peak Concurrent Invocations"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="peak-concurrent-invocations" />
          <metric-dmr name="Wait Time"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="wait-time" />
          <metric-dmr name="Pool Availabile Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-available-count" />
          <metric-dmr name="Pool Create Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-create-count" />
          <metric-dmr name="Pool Current Size"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-current-size" />
          <metric-dmr name="Pool Max Size"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-max-size" />
          <metric-dmr name="Pool Remove Count"
                      interval="5"
                      timeUnits="minutes"
                      path="/"
                      attribute="pool-remove-count" />
        </metric-set-dmr>

        <metric-set-dmr name="Datasource JDBC Metrics" enabled="true">
          <metric-dmr name="Prepared Statement Cache Access Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=jdbc"
                      attribute="PreparedStatementCacheAccessCount" />
          <metric-dmr name="Prepared Statement Cache Add Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=jdbc"
                      attribute="PreparedStatementCacheAddCount" />
          <metric-dmr name="Prepared Statement Cache Current Size"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=jdbc"
                      attribute="PreparedStatementCacheCurrentSize" />
          <metric-dmr name="Prepared Statement Cache Delete Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=jdbc"
                      attribute="PreparedStatementCacheDeleteCount" />
          <metric-dmr name="Prepared Statement Cache Hit Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=jdbc"
                      attribute="PreparedStatementCacheHitCount" />
          <metric-dmr name="Prepared Statement Cache Miss Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=jdbc"
                      attribute="PreparedStatementCacheMissCount" />
        </metric-set-dmr>

        <metric-set-dmr name="Datasource Pool Metrics" enabled="true">
          <metric-dmr name="Active Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="ActiveCount" />
          <metric-dmr name="Available Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="AvailableCount" />
          <metric-dmr name="Average Blocking Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="AverageBlockingTime" />
          <metric-dmr name="Average Creation Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="AverageCreationTime" />
          <metric-dmr name="Average Get Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="AverageGetTime" />
          <metric-dmr name="Blocking Failure Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="BlockingFailureCount" />
          <metric-dmr name="Created Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="CreatedCount" />
          <metric-dmr name="Destroyed Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="DestroyedCount" />
          <metric-dmr name="Idle Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="IdleCount" />
          <metric-dmr name="In Use Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="InUseCount" />
          <metric-dmr name="Max Creation Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="MaxCreationTime" />
          <metric-dmr name="Max Get Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="MaxGetTime" />
          <metric-dmr name="Max Used Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="MaxUsedCount" />
          <metric-dmr name="Max Wait Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="MaxWaitCount" />
          <metric-dmr name="Max Wait Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="MaxWaitTime" />
          <metric-dmr name="Timed Out"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="TimedOut" />
          <metric-dmr name="Total Blocking Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="TotalBlockingTime" />
          <metric-dmr name="Total Creation Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="TotalCreationTime" />
          <metric-dmr name="Total Get Time"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="TotalGetTime" />
          <metric-dmr name="Wait Count"
                      interval="10"
                      timeUnits="minutes"
                      path="/statistics=pool"
                      attribute="WaitCount" />
        </metric-set-dmr>

        <metric-set-dmr name="Transactions Metrics" enabled="true">
          <metric-dmr name="Number of Aborted Transactions"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-aborted-transactions" />
          <metric-dmr name="Number of Application Rollbacks"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-application-rollbacks" />
          <metric-dmr name="Number of Committed Transactions"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-committed-transactions" />
          <metric-dmr name="Number of Heuristics"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-heuristics" />
          <metric-dmr name="Number of In-Flight Transactions"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-inflight-transactions" />
          <metric-dmr name="Number of Nested Transactions"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-nested-transactions" />
          <metric-dmr name="Number of Resource Rollbacks"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-resource-rollbacks" />
          <metric-dmr name="Number of Timed Out Transactions"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-timed-out-transactions" />
          <metric-dmr name="Number of Transactions"
                      interval="10"
                      timeUnits="minutes"
                      path="/"
                      attribute="number-of-transactions" />
        </metric-set-dmr>

        <avail-set-dmr name="Server Availability" enabled="true">
          <avail-dmr name="App Server"
                     interval="30"
                     timeUnits="seconds"
                     path="/"
                     attribute="server-state"
                     upRegex="run.*" />
        </avail-set-dmr>

        <avail-set-dmr name="Deployment Status" enabled="true">
          <avail-dmr name="Deployment Status"
                     interval="1"
                     timeUnits="minutes"
                     path="/"
                     attribute="status"
                     upRegex="OK" />
        </avail-set-dmr>

        <resource-type-set-dmr name="Main" enabled="true">
          <resource-type-dmr name="WildFly Server"
                             resourceNameTemplate="WildFly Server"
                             path="/"
                             metricSets="WildFly Memory Metrics,WildFly Threading Metrics"
                             availSets="Server Availability" />
        </resource-type-set-dmr>

        <resource-type-set-dmr name="Hawkular" enabled="true">
          <resource-type-dmr name="Bus Broker"
                             resourceNameTemplate="Bus Broker"
                             path="/subsystem=hawkular-bus-broker"
                             parents="WildFly Server"/>
        </resource-type-set-dmr>

         <resource-type-set-dmr name="Deployment" enabled="true">
            <resource-type-dmr name="Deployment"
                               resourceNameTemplate="Deployment [%2]"
                               path="/deployment=*"
                               parents="WildFly Server"
                               metricSets="Undertow Metrics"
                               availSets="Deployment Status" />

            <resource-type-dmr name="SubDeployment"
                               resourceNameTemplate="SubDeployment [%-]"
                               path="/subdeployment=*"
                               parents="Deployment"
                               metricSets="Undertow Metrics" />
         </resource-type-set-dmr>

        <resource-type-set-dmr name="Web Component" enabled="true">
          <resource-type-dmr name="Servlet"
                             resourceNameTemplate="Servlet [%-]"
                             path="/subsystem=undertow/servlet=*"
                             parents="Deployment,SubDeployment"
                             metricSets="Servlet Metrics" />
        </resource-type-set-dmr>

        <resource-type-set-dmr name="EJB" enabled="true">
          <resource-type-dmr name="Singleton EJB"
                             resourceNameTemplate="Singleton EJB [%-]"
                             path="/subsystem=ejb3/singleton-bean=*"
                             parents="Deployment,SubDeployment"
                             metricSets="Singleton EJB Metrics" />

          <resource-type-dmr name="Message Driven EJB"
                             resourceNameTemplate="Message Driven EJB [%-]"
                             path="/subsystem=ejb3/message-driven-bean=*"
                             parents="Deployment,SubDeployment"
                             metricSets="Message Driven EJB Metrics" />

          <resource-type-dmr name="Stateless Session EJB"
                             resourceNameTemplate="Stateless Session EJB [%-]"
                             path="/subsystem=ejb3/stateless-session-bean=*"
                             parents="Deployment,SubDeployment"
                             metricSets="Stateless Session EJB Metrics" />
        </resource-type-set-dmr>

        <resource-type-set-dmr name="Datasource" enabled="true">
          <resource-type-dmr name="Datasource"
                             resourceNameTemplate="Datasource [%-]"
                             path="/subsystem=datasources/data-source=*"
                             parents="WildFly Server"
                             metricSets="Datasource Pool Metrics,Datasource JDBC Metrics" />
        </resource-type-set-dmr>

        <resource-type-set-dmr name="Transaction Manager" enabled="true">
          <resource-type-dmr name="Transaction Manager"
                             resourceNameTemplate="Transaction Manager"
                             path="/subsystem=transactions"
                             parents="WildFly Server"
                             metricSets="Transactions Metrics" />
        </resource-type-set-dmr>

        <managed-servers>
          <remote-dmr name="Another Remote Server"
                      enabled="false"
                      host="localhost"
                      port="9990"
                      username="adminUser"
                      password="adminPass"
                      resourceTypeSets="Main,Deployment,Web Component,EJB,Datasource,Transaction Manager" />

          <local-dmr enabled="true"
                     resourceTypeSets="Main,Deployment,Web Component,EJB,Datasource,Transaction Manager" />

        </managed-servers>

      </subsystem>

      <!-- Keycloak-related - our secured deployments (important) -->
      <subsystem xmlns="urn:jboss:domain:keycloak:1.0">
        <auth-server name="main-auth-server">
          <enabled>true</enabled>
          <web-context>auth</web-context>
        </auth-server>
        <realm name="hawkular">
          <auth-server-url>http://localhost:8080/auth</auth-server-url>
          <ssl-required>none</ssl-required>
        </realm>
        <secure-deployment name="hawkular-accounts.war">
          <realm>hawkular</realm>
          <resource>hawkular-accounts-backend</resource>
          <use-resource-role-mappings>true</use-resource-role-mappings>
          <enable-cors>true</enable-cors>
          <enable-basic-auth>true</enable-basic-auth>
          <credential name="secret"><xsl:value-of select="$uuid.hawkular.accounts.backend" /></credential>
        </secure-deployment>
        <secure-deployment name="hawkular-integrated-inventory-rest.war">
          <realm>hawkular</realm>
          <resource>hawkular-accounts-backend</resource>
          <use-resource-role-mappings>true</use-resource-role-mappings>
          <enable-cors>true</enable-cors>
          <enable-basic-auth>true</enable-basic-auth>
          <credential name="secret">
            <xsl:value-of select="$uuid.hawkular.accounts.backend"/>
          </credential>
        </secure-deployment>
      </subsystem>
    </xsl:copy>
  </xsl:template>

  <!-- Keycloak-related - security-domain definitions -->
  <xsl:template match="node()[name(.)='security-domains']">
    <xsl:copy>
      <xsl:apply-templates select="node()[name(.)='security-domain']"/>
      <security-domain name="keycloak">
        <authentication>
          <login-module code="org.keycloak.adapters.jboss.KeycloakLoginModule" flag="required"/>
        </authentication>
      </security-domain>
      <security-domain name="sp" cache-type="default">
        <authentication>
          <login-module code="org.picketlink.identity.federation.bindings.wildfly.SAML2LoginModule" flag="required"/>
        </authentication>
      </security-domain>
    </xsl:copy>
  </xsl:template>

  <!-- Add a cache for Hawkular Accounts -->
  <xsl:template match="node()[name(.)='cache-container'][1]">
    <xsl:copy>
      <xsl:copy-of select="node()|@*"/>
    </xsl:copy>
    <cache-container name="hawkular-accounts" default-cache="role-cache">
      <local-cache name="role-cache"/>
      <local-cache name="operation-cache"/>
    </cache-container>
  </xsl:template>

  <!-- copy everything else as-is -->
  <xsl:template match="node()|@*">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>
