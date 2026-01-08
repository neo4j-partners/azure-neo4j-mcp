// =============================================================================
// Neo4j Aura SSO - Entra App Registration Only
// Standalone template for deploying just the Azure Entra app registration
// without the full infrastructure (Container Apps, ACR, Key Vault, etc.)
//
// Use this when you only need to create the app registration for Neo4j Aura SSO.
// This is a subscription-scoped deployment (no resource group required).
//
// Usage:
//   ./scripts/deploy.sh app-registration
//
// Or manually:
//   az deployment sub create \
//     --location eastus \
//     --template-file infra/app-registration.bicep \
//     --parameters appDisplayName="Neo4j Aura SSO"
// =============================================================================

targetScope = 'subscription'

extension microsoftGraphV1

// =============================================================================
// Parameters
// =============================================================================

@description('Display name for the Entra app registration')
param appDisplayName string = 'Neo4j Aura SSO'

@description('Unique name for the application (must be unique within tenant)')
param appUniqueName string = 'neo4j-aura-sso-${uniqueString(subscription().subscriptionId)}'

// =============================================================================
// Resources
// =============================================================================

// Application registration for Neo4j Aura SSO
resource neo4jSsoApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appUniqueName
  displayName: appDisplayName
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: [
      'https://login.neo4j.com/login/callback'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: true
    }
  }
  requiredResourceAccess: [
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
      resourceAccess: [
        {
          id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d' // User.Read
          type: 'Scope'
        }
        {
          id: '64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0' // email
          type: 'Scope'
        }
        {
          id: '14dad69e-099b-42c9-810b-d002981feec1' // profile
          type: 'Scope'
        }
        {
          id: '37f7f235-527c-4136-accd-4a02d197296e' // openid
          type: 'Scope'
        }
      ]
    }
  ]
}

// Service principal for the application
resource neo4jSsoSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: neo4jSsoApp.appId
}

// =============================================================================
// Outputs
// =============================================================================

@description('Application (client) ID - use this when configuring Neo4j Aura SSO')
output clientId string = neo4jSsoApp.appId

@description('Application object ID')
output objectId string = neo4jSsoApp.id

@description('Service principal object ID')
output servicePrincipalId string = neo4jSsoSp.id

@description('Azure tenant ID')
output tenantId string = tenant().tenantId

@description('OpenID Connect discovery URI for Neo4j Aura SSO configuration')
#disable-next-line no-hardcoded-env-urls
output discoveryUri string = 'https://login.microsoftonline.com/${tenant().tenantId}/v2.0/.well-known/openid-configuration'
