// =============================================================================
// Entra App Registration for Neo4j Aura SSO
// Creates an Azure Entra (formerly Azure AD) application registration
// configured for Neo4j Aura Single Sign-On.
//
// Requirements:
// - Deploying user needs Application.ReadWrite.All permission in Microsoft Graph
// - Client secret must be created manually in Azure Portal after deployment
// - Bicep CLI version 0.36.1 or later
//
// Post-deployment steps:
// 1. Go to Azure Portal > App registrations > [this app] > Certificates & secrets
// 2. Create a new client secret and copy the Value (not the secret ID)
// 3. Configure Neo4j Aura SSO with:
//    - Client ID: Use the appId output from this deployment
//    - Client Secret: The value from step 2
//    - Discovery URI: Use the discoveryUri output from this deployment
// =============================================================================

extension microsoftGraphV1

// =============================================================================
// Parameters
// =============================================================================

@description('Application display name shown in Azure Portal')
param displayName string

@description('Unique name for the application (must be unique within tenant)')
param uniqueName string

// =============================================================================
// Resources
// =============================================================================

// Application registration for Neo4j Aura SSO
resource neo4jSsoApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: uniqueName
  displayName: displayName
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
// Required for users to actually sign in via this app
resource neo4jSsoSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: neo4jSsoApp.appId
}

// =============================================================================
// Outputs
// =============================================================================

@description('Application (client) ID - use this when configuring Neo4j Aura SSO')
output appId string = neo4jSsoApp.appId

@description('Application object ID')
output objectId string = neo4jSsoApp.id

@description('Service principal object ID')
output servicePrincipalId string = neo4jSsoSp.id

@description('Azure tenant ID - use to construct the discovery URI')
output tenantId string = tenant().tenantId

@description('OpenID Connect discovery URI for Neo4j Aura SSO configuration')
#disable-next-line no-hardcoded-env-urls
output discoveryUri string = 'https://login.microsoftonline.com/${tenant().tenantId}/v2.0/.well-known/openid-configuration'
