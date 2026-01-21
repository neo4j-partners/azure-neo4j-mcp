// =============================================================================
// Key Vault Module
// Creates an Azure Key Vault with RBAC authorization for storing secrets.
// Configures managed identity access with Key Vault Secrets User role.
// Stores Neo4j connection credentials and MCP API key.
// =============================================================================

@description('Name of the Key Vault')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region for the Key Vault')
param location string

@description('Tags to apply to the Key Vault')
param tags object = {}

@description('Principal ID of the managed identity to grant Key Vault Secrets User access')
param identityPrincipalId string

@description('Principal ID of the deploying user to grant Key Vault Secrets Officer access')
param deployerPrincipalId string = ''

@description('Neo4j database connection URI')
@secure()
param neo4jUri string

@description('Neo4j database username')
@secure()
param neo4jUsername string

@description('Neo4j database password')
@secure()
param neo4jPassword string

@description('Neo4j database name')
@secure()
param neo4jDatabase string

@description('MCP API key for authentication')
@secure()
param mcpApiKey string

// Built-in role definitions using existing resource pattern (Microsoft recommended)
// Reference: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/scenarios-rbac

@description('Key Vault Secrets User - read secret contents')
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

@description('Key Vault Secrets Officer - read/write/delete secrets')
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

// Use latest stable API version (2025-05-01)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.keyvault/vaults
resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    // Enable RBAC authorization instead of access policies
    // This is the recommended approach for new deployments
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7  // Minimum for demo, reduces cleanup time
    // Note: enablePurgeProtection is not set - once enabled it cannot be disabled
    // For production, set enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Grant Key Vault Secrets User role to the managed identity
// This allows the Container App to read secrets using the managed identity
resource secretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, identityPrincipalId, keyVaultSecretsUserRole.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'  // Required for managed identities to avoid intermittent errors
    description: 'Allow Container App managed identity to read secrets for Neo4j MCP Server'
  }
}

// Grant Key Vault Secrets Officer role to the deploying user
// This allows the deployer to update secrets via redeploy command
resource secretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultSecretsOfficerRole.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRole.id
    principalId: deployerPrincipalId
    principalType: 'User'
    description: 'Allow deployer to update secrets during redeploy operations'
  }
}

// =============================================================================
// Secrets
// =============================================================================

// Neo4j Connection URI
resource secretNeo4jUri 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'neo4j-uri'
  properties: {
    value: neo4jUri
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Neo4j Username
resource secretNeo4jUsername 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'neo4j-username'
  properties: {
    value: neo4jUsername
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Neo4j Password
resource secretNeo4jPassword 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'neo4j-password'
  properties: {
    value: neo4jPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Neo4j Database Name
resource secretNeo4jDatabase 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'neo4j-database'
  properties: {
    value: neo4jDatabase
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// MCP API Key
resource secretMcpApiKey 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
  parent: keyVault
  name: 'mcp-api-key'
  properties: {
    value: mcpApiKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the Key Vault')
output id string = keyVault.id

@description('Name of the Key Vault')
output name string = keyVault.name

@description('URI of the Key Vault')
output vaultUri string = keyVault.properties.vaultUri

