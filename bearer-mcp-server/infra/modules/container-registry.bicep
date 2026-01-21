// =============================================================================
// Container Registry Module
// Creates an Azure Container Registry for storing Docker images.
// Configures managed identity access with AcrPull role for secure image pulls.
// =============================================================================

@description('Name of the container registry (must be globally unique, alphanumeric only)')
@minLength(5)
@maxLength(50)
param name string

@description('Azure region for the container registry')
param location string

@description('Tags to apply to the container registry')
param tags object = {}

@description('SKU for the container registry')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('Principal ID of the managed identity to grant AcrPull access')
param acrPullPrincipalId string

// AcrPull built-in role definition ID
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

// Use latest stable API version (2025-11-01)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.containerregistry/registries
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: false  // Disabled for security - use managed identity
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

// Grant AcrPull role to the managed identity
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, acrPullPrincipalId, acrPullRoleDefinitionId)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: acrPullPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the container registry')
output id string = containerRegistry.id

@description('Name of the container registry')
output name string = containerRegistry.name

@description('Login server URL of the container registry')
output loginServer string = containerRegistry.properties.loginServer
