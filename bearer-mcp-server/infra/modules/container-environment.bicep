// =============================================================================
// Container Apps Environment Module
// Creates an Azure Container Apps Environment linked to Log Analytics.
// Uses consumption workload profile for cost-effective deployments.
// =============================================================================

@description('Name of the Container Apps Environment')
@minLength(1)
@maxLength(64)
param name string

@description('Azure region for the Container Apps Environment')
param location string

@description('Tags to apply to the environment')
param tags object = {}

@description('Customer ID of the Log Analytics workspace')
param logAnalyticsCustomerId string

@description('Shared key for Log Analytics workspace')
@secure()
param logAnalyticsSharedKey string

// Use latest stable API version (2025-07-01)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.app/2025-07-01/managedenvironments
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the Container Apps Environment')
output id string = containerAppsEnvironment.id

@description('Name of the Container Apps Environment')
output name string = containerAppsEnvironment.name

@description('Default domain of the Container Apps Environment')
output defaultDomain string = containerAppsEnvironment.properties.defaultDomain

@description('Static IP address of the Container Apps Environment')
output staticIp string = containerAppsEnvironment.properties.staticIp
