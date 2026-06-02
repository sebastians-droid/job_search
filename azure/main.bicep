// BIDX V1 — Azure infrastructure (Step 2)
// Deploy: az deployment group create -g <rg> -f main.bicep -p @parameters.json

@description('Azure region, e.g. eastus')
param location string = resourceGroup().location

@description('Short prefix for resource names')
param prefix string = 'bidx'

@description('Globally unique ACR name (letters/numbers only, 5–50 chars)')
param acrName string

@description('Globally unique Key Vault name')
param keyVaultName string

@description('Container image (update after first ACR build)')
param containerImage string

@description('Job timeout in seconds (scraper can run 60–90+ minutes)')
param jobReplicaTimeout int = 10800

@description('Enable built-in cron schedule (false = Power Automate triggers only)')
param enableSchedule bool = false

@description('Cron in UTC — 0 11 * * * = 6am EST; ignored when enableSchedule is false')
param scheduleCron string = '0 11 * * *'

@description('Full resource ID of an existing Log Analytics workspace (Option C). Leave empty to create a new workspace in this resource group.')
param existingLogAnalyticsWorkspaceId string = ''

@description('Deploy the Container Apps Job. Set false for pass 1 (infra only); deploy.ps1 sets true on pass 2 after Key Vault secrets exist.')
param deployScraperJob bool = true

var useExistingLogAnalytics = !empty(existingLogAnalyticsWorkspaceId)
var logWorkspaceName = '${prefix}-logs'
var environmentName = '${prefix}-cae'
var jobName = '${prefix}-scraper-job'
var identityName = '${prefix}-job-identity'
var existingLaParts = split(existingLogAnalyticsWorkspaceId, '/')
var existingLaResourceGroupName = useExistingLogAnalytics ? existingLaParts[4] : ''
var existingLaWorkspaceName = useExistingLogAnalytics ? existingLaParts[8] : ''

resource newLogAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (!useExistingLogAnalytics) {
  name: logWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource existingLogAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = if (useExistingLogAnalytics) {
  scope: resourceGroup(subscription().subscriptionId, existingLaResourceGroupName)
  name: existingLaWorkspaceName
}

var logAnalyticsCustomerId = useExistingLogAnalytics ? existingLogAnalytics!.properties.customerId : newLogAnalytics!.properties.customerId

var logAnalyticsSharedKey = useExistingLogAnalytics ? existingLogAnalytics!.listKeys().primarySharedKey : newLogAnalytics!.listKeys().primarySharedKey

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
  }
}

resource jobIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, jobIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
    principalId: jobIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, jobIdentity.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
    principalId: jobIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

var jobTriggerConfig = enableSchedule
  ? {
      triggerType: 'Schedule'
      replicaTimeout: jobReplicaTimeout
      replicaRetryLimit: 0
      scheduleTriggerConfig: {
        cronExpression: scheduleCron
        parallelism: 1
        replicaCompletionCount: 1
      }
    }
  : {
      triggerType: 'Manual'
      replicaTimeout: jobReplicaTimeout
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
    }

resource scraperJob 'Microsoft.App/jobs@2024-03-01' = if (deployScraperJob) {
  name: jobName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${jobIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnv.id
    configuration: union(jobTriggerConfig, {
      secrets: [
        {
          name: 'bidx-username'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/BIDX-USERNAME'
          identity: jobIdentity.id
        }
        {
          name: 'bidx-password'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/BIDX-PASSWORD'
          identity: jobIdentity.id
        }
      ]
    })
    template: {
      containers: [
        {
          name: 'bidx-scraper'
          image: containerImage
          env: [
            {
              name: 'BIDX_USERNAME'
              secretRef: 'bidx-username'
            }
            {
              name: 'BIDX_PASSWORD'
              secretRef: 'bidx-password'
            }
            {
              name: 'BIDX_HEADLESS'
              value: 'true'
            }
            {
              name: 'CHROME_BIN'
              value: '/usr/bin/google-chrome'
            }
          ]
          resources: {
            cpu: json('2.0')
            memory: '4Gi'
          }
        }
      ]
    }
  }
}

output acrLoginServer string = acr.properties.loginServer
output keyVaultUri string = keyVault.properties.vaultUri
output containerAppsEnvironmentId string = containerEnv.id
output jobName string = deployScraperJob ? scraperJob.name : ''
output jobResourceId string = deployScraperJob ? scraperJob.id : ''
output managedIdentityClientId string = jobIdentity.properties.clientId
output resourceGroupName string = resourceGroup().name
