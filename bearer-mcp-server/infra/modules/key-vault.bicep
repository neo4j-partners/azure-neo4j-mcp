// =============================================================================
// Key Vault Module - Bearer Token Mode
// Creates an Azure Key Vault for storing connection configuration only.
//
// In bearer token mode, NO CREDENTIALS are stored:
// - No NEO4J_USERNAME or NEO4J_PASSWORD (authentication via bearer tokens)
// - No MCP_API_KEY (clients authenticate via identity provider)
//
// Only connection information is stored:
// - neo4j-uri: Database connection string
// - neo4j-database: Target database name
//
// This Key Vault serves as a configuration store, not a secrets store.
// =============================================================================

@description('Name of the Key Vault')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region for the Key Vault')
param location string

@description('Tags to apply to the Key Vault')
param tags object = {}

@description('Principal ID of the deploying user to grant access during deployment')
param deployerPrincipalId string = ''

@description('Neo4j database connection URI')
@secure()
param neo4jUri string

@description('Neo4j database name')
param neo4jDatabase string = 'neo4j'

// Built-in role definitions
@description('Key Vault Secrets Officer - read/write/delete secrets')
resource keyVaultSecretsOfficerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

// Use latest stable API version (2025-05-01)
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
    // Enable RBAC authorization (recommended best practice)
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Grant Key Vault Secrets Officer role to the deploying user
resource secretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, keyVaultSecretsOfficerRole.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRole.id
    principalId: deployerPrincipalId
    principalType: 'User'
    description: 'Allow deployer to manage Key Vault secrets'
  }
}

// =============================================================================
// Configuration Values (NOT Credentials)
// =============================================================================

// Neo4j Connection URI
// This is connection information, not a credential
// The URI format (neo4j+s://) doesn't contain authentication
resource configNeo4jUri 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
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

// Neo4j Database Name
resource configNeo4jDatabase 'Microsoft.KeyVault/vaults/secrets@2025-05-01' = {
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

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the Key Vault')
output id string = keyVault.id

@description('Name of the Key Vault')
output name string = keyVault.name

@description('URI of the Key Vault')
output vaultUri string = keyVault.properties.vaultUri
