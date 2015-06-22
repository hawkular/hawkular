/**
 * Copyright 2015 Red Hat, Inc. and/or its affiliates
 * and other contributors as indicated by the @author tags.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.hawkular.integration.test

import java.util.Map;

import org.apache.http.auth.AuthScope;
import org.apache.http.auth.UsernamePasswordCredentials;
import org.apache.http.impl.client.LaxRedirectStrategy;
import org.hawkular.inventory.api.model.Environment
import org.hawkular.inventory.api.model.Metric
import org.hawkular.inventory.api.model.MetricType
import org.hawkular.inventory.api.model.MetricUnit;
import org.hawkular.inventory.api.model.Resource
import org.hawkular.inventory.api.model.ResourceType
import org.hawkular.inventory.api.model.Tenant

import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertEquals;

import org.junit.Assert;
import org.junit.Test


class Scenario1ITest extends AbstractTestBase {

    static final String urlTypeId = "URL"
    static final String environmentId = "test"
    static final String statusCodeTypeId = "status.code.type"
    static final String durationTypeId = "status.duration.type"

    @Test
    public void testScenario() throws Exception {
        //def response = client.get(path: "/hawkular-accounts/organizations")
        def response = client.get(path: "/hawkular-accounts/personas/current")
        assertResponseOk(response.status)
        String tenantId = response.data.id
        // println "tenantId = $tenantId"

        /* assert the test environment exists */
        /* There is a race condition when WildFly agent is enabled:
           both this test and Agent trigger the autocreation of test entities simultaneously,
           and one of them may get only a partially initialized state.
           That is why we do several delayed attempts do perform the first request.
         */
        String path = "/hawkular/inventory/$tenantId/environments/$environmentId";
        int attemptCount = 5;
        int delay = 500;
        for (int i = 0; i < attemptCount; i++) {
            try {
                response = client.get(path: path)
                /* all is well, we can leave the loop */
                break;
            } catch (groovyx.net.http.HttpResponseException e) {
                /* some initial attempts may fail */
            }
            println "'$path' not ready yet, about to retry after $delay ms"
            /* sleep one second */
            Thread.sleep(delay);
        }
        if (response.status != 200) {
            Assert.fail("Getting path '$path' returned status ${response.status}, tried $attemptCount times");
        }
        assertEquals(environmentId, response.data.id)

        /* assert the URL resource type exists */
        response = client.get(path: "/hawkular/inventory/$tenantId/resourceTypes/$urlTypeId")
        assertResponseOk(response.status)
        assertEquals(urlTypeId, response.data.id)

        /* assert the metric types exist */
        response = client.get(path: "/hawkular/inventory/$tenantId/metricTypes/$statusCodeTypeId")
        assertResponseOk(response.status)
        response = client.get(path: "/hawkular/inventory/$tenantId/metricTypes/$durationTypeId")
        assertResponseOk(response.status)

        /* create a URL */
        String resourceId = UUID.randomUUID().toString();
        def newResource = Resource.Blueprint.builder().withId(resourceId)
                .withResourceType(urlTypeId).withProperty("url", "http://hawkular.org").build()
        response = client.post(path: "/hawkular/inventory/$tenantId/$environmentId/resources", body : newResource)
        assertResponseOk(response.status)

        /* create the metrics */
        String statusCodeId = UUID.randomUUID().toString();
        def codeMetric = Metric.Blueprint.builder().withMetricTypeId(statusCodeTypeId).withId(statusCodeId).build();
        response = client.post(path: "/hawkular/inventory/$tenantId/$environmentId/metrics", body: codeMetric)
        assertResponseOk(response.status)

        String durationId = UUID.randomUUID().toString();
        def durationMetric = Metric.Blueprint.builder().withMetricTypeId(durationTypeId).withId(durationId).build();
        response = client.post(path: "/hawkular/inventory/$tenantId/$environmentId/metrics", body: durationMetric)
        assertResponseOk(response.status)

        /* assign metrics to the resource */
        response = client.post(path: "/hawkular/inventory/$tenantId/$environmentId/resources/$resourceId/metrics",
        body: [
            statusCodeId,
            durationId]
        )
        assertResponseOk(response.status)

        /* Pinger should start pinging now but we do not want to wait */

        // 9 simulate ping + response - metrics for ~ the last 30 minutes

        /* Wait till metrics gets initialized */
        path = "/hawkular/metrics/status"
        delay = 1000
        attemptCount = 30
        String metricsServiceStatus;
        for (int i = 0; i < attemptCount; i++) {
            response = client.get(path: path)
            if (response.status == 200) {
                metricsServiceStatus = response.data.MetricsService
                if ("STARTED".equals(metricsServiceStatus)) {
                    /* the service has started - we can leave the loop */
                    break;
                }
            }
            println "'MetricsService' not ready yet, about to retry after $delay ms"
            /* sleep one second */
            Thread.sleep(delay);
        }
        if (!"STARTED".equals(metricsServiceStatus)) {
            Assert.fail("MetricsService status still '$metricsServiceStatus' after trying $attemptCount times" +
                " with delay $delay ms.")
        }


        for (int i = -30 ; i <-3 ; i++ ) {
            postMetricValue(tenantId, resourceId, statusCodeId, 100 + i, i)
            postMetricValue(tenantId, resourceId, durationId, 200, i)
        }

        postMetricValue(tenantId, resourceId, statusCodeId, 500, -2)
        postMetricValue(tenantId, resourceId, statusCodeId, 404, -1)
        postMetricValue(tenantId, resourceId, statusCodeId, 200, 0)
        postMetricValue(tenantId, resourceId, statusCodeId, 42, 0)

        /* Get values for a chart - last 4h data */
        def end = System.currentTimeMillis()
        def start = end - 4 * 3600 * 1000 // 4h earlier
        response = client.get(path: "/hawkular/metrics/gauges/${resourceId}.$statusCodeId/data",
                query: [start: start, end: end], headers: ["Hawkular-Tenant": tenantId])
        assertEquals(31, response.data.size());

        response = client.get(path: "/hawkular/metrics/gauges/${resourceId}.$durationId/data",
                query: [start: start, end: end], headers: ["Hawkular-Tenant": tenantId])
        assertEquals(27, response.data.size());

        /* TODO: define an alert */
        // response = client.post(path: "alerts/triggers/")

    }

    private void assertResponseOk(int responseCode) {
        assertTrue("Response code should be 2xx or 304 but was "+ responseCode,
                (responseCode >= 200 && responseCode < 300) || responseCode == 304)
    }

    private void postMetricValue(String tenantId, String resourceId, String metricName, int value, int timeSkewMinutes = 0) {
        def response
        def now = System.currentTimeMillis()
        def tmp = "$resourceId.$metricName"

        long time = now + (timeSkewMinutes * 60 * 1000)

        response = client.post(path: "/hawkular/metrics/gauges/$tmp/data",
            headers: ["Hawkular-Tenant": tenantId],
            body: [
                [timestamp: time, value: value]
            ])
        assertResponseOk(response.status)
    }
}