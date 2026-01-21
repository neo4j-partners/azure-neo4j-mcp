// =============================================================================
// Managed Identity Module
// Creates a user-assigned managed identity for Azure Container Apps.
// In bearer mode, this identity is used only for ACR image pulls.
// Key Vault access is not needed since no secrets are retrieved at runtime.
// =============================================================================

@description('Name of the user-assigned managed identity')
@minLength(3)
@maxLength(128)
param name string

@description('Azure region for the managed identity')
param location string

@description('Tags to apply to the managed identity')
param tags object = {}

// Use latest stable API version (2024-11-30)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.managedidentity/userassignedidentities
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: tags
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the managed identity')
output id string = managedIdentity.id

@description('Principal ID of the managed identity (used for role assignments)')
output principalId string = managedIdentity.properties.principalId

@description('Client ID of the managed identity')
output clientId string = managedIdentity.properties.clientId

@description('Name of the managed identity')
output name string = managedIdentity.name
