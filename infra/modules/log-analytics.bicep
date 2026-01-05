// =============================================================================
// Log Analytics Workspace Module
// Creates a Log Analytics workspace for Container Apps Environment telemetry.
// Collects container logs, metrics, and provides query capabilities.
// =============================================================================

@description('Name of the Log Analytics workspace')
param name string

@description('Azure region for the Log Analytics workspace')
param location string

@description('Tags to apply to the workspace')
param tags object = {}

@description('Number of days to retain logs (30-730)')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU for the workspace. Note: Free tier has 500MB/day limit and 7-day max retention.')
@allowed([
  'Free'        // Limited: 500MB/day, 7-day retention max
  'PerGB2018'   // Recommended: Pay-per-GB, flexible retention
  'Standalone'  // Legacy: Fixed capacity pricing
])
param skuName string = 'PerGB2018'

// Use latest stable API version (2025-07-01)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.operationalinsights/workspaces
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: skuName
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the Log Analytics workspace')
output id string = logAnalyticsWorkspace.id

@description('Name of the Log Analytics workspace')
output name string = logAnalyticsWorkspace.name

@description('Customer ID (workspace ID) for the Log Analytics workspace')
output customerId string = logAnalyticsWorkspace.properties.customerId
