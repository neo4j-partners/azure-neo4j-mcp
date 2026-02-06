// =============================================================================
// Neo4j MCP Server - Bearer Token Authentication Deployment
// Main Bicep template for single-container deployment with native bearer auth.
//
// This deployment uses the official Neo4j MCP server Docker image from Docker Hub
// (docker.io/mcp/neo4j) with HTTP mode and bearer token authentication. Clients
// authenticate via their identity provider and pass JWT tokens directly to the
// MCP server, which forwards them to Neo4j.
//
// Key Differences from simple-mcp-server:
// - Single container (no Nginx auth proxy)
// - No static API key or database credentials stored
// - Bearer tokens passed through to Neo4j for SSO/OIDC authentication
// - Requires Neo4j Enterprise with OIDC configured
// - Uses official Docker Hub image (no ACR or custom build needed)
//
// Resources created:
// - Log Analytics Workspace (for container telemetry)
// - Azure Key Vault (minimal - only connection info, no credentials)
// - Container Apps Environment
// - Container App (single Neo4j MCP Server container from Docker Hub)
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources (used to generate unique names)')
@minLength(3)
@maxLength(20)
param baseName string = 'neo4jmcp'

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  project: 'neo4j-mcp-server-bearer'
  environment: environment
  deployedBy: 'bicep'
  authMode: 'bearer-token'
}

// =============================================================================
// Connection Parameters (No Credentials - Bearer Auth Mode)
// =============================================================================

@description('Neo4j database connection URI (e.g., neo4j+s://xxx.databases.neo4j.io)')
@secure()
param neo4jUri string

@description('Neo4j database name (default: neo4j)')
param neo4jDatabase string = 'neo4j'

@description('Neo4j MCP Server container image (default: official Docker Hub image)')
param mcpServerImage string = 'docker.io/mcp/neo4j:latest'

@description('Principal ID of the deploying user (for Key Vault access during deployment)')
param deployerPrincipalId string = ''

@description('Enable read-only mode (disables write-cypher tool)')
param readOnlyMode bool = true

@description('Allowed CORS origins (comma-separated, or * for all)')
param allowedOrigins string = ''

@description('Deploy container app (set to false for foundation-only deployment)')
param deployContainerApp bool = true

// =============================================================================
// Variables
// =============================================================================

// Generate unique suffix based on resource group ID for globally unique names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Deployment timestamp for resources that need unique names on each deployment
param deploymentTimestamp string = utcNow('yyyyMMddHHmmss')

// Resource names - using 'b' prefix to distinguish from simple-mcp-server and keep names short
var logAnalyticsName = '${baseName}-b-logs-${environment}'
var keyVaultName = 'kv-b-${take(uniqueSuffix, 4)}-${take(deploymentTimestamp, 10)}'
var containerEnvironmentName = '${baseName}-b-env-${environment}'
// Ensure container app name is max 32 chars: baseName(max 20) + '-b-' (3) + env (max 7) = 30, but use take() for safety
var containerAppName = take('${baseName}-b-${environment}', 32)

// =============================================================================
// Phase 1: Foundation Resources
// =============================================================================

// Log Analytics Workspace
// Required by Container Apps Environment for telemetry
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    retentionInDays: 30
    skuName: 'PerGB2018'
  }
}

// =============================================================================
// Phase 2: Configuration Storage (Minimal - No Credentials)
// =============================================================================

// Azure Key Vault
// In bearer mode, only stores connection info (URI, database name)
// NO credentials stored - authentication via bearer tokens at runtime
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    deployerPrincipalId: deployerPrincipalId
    neo4jUri: neo4jUri
    neo4jDatabase: neo4jDatabase
  }
}

// =============================================================================
// Phase 3: Container Environment
// =============================================================================

// Reference to Log Analytics workspace for listKeys
resource logAnalyticsWorkspaceRef 'Microsoft.OperationalInsights/workspaces@2025-07-01' existing = {
  name: logAnalyticsName
  dependsOn: [
    logAnalytics
  ]
}

// Container Apps Environment
module containerEnvironment 'modules/container-environment.bicep' = {
  name: 'deploy-container-environment'
  params: {
    name: containerEnvironmentName
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalyticsWorkspaceRef.listKeys().primarySharedKey
  }
}

// =============================================================================
// Phase 4: Container App (Single Container - No Proxy)
// =============================================================================

// Container App - Neo4j MCP Server with Bearer Token Authentication
// Uses official Docker Hub image (docker.io/mcp/neo4j)
// Single container deployment - no Nginx proxy needed
// Authentication handled by MCP server passing tokens to Neo4j
// Conditional: only deploy when deployContainerApp=true
module containerApp 'modules/container-app.bicep' = if (deployContainerApp) {
  name: 'deploy-container-app'
  params: {
    name: containerAppName
    location: location
    tags: tags
    containerAppsEnvironmentId: containerEnvironment.outputs.id
    mcpServerImage: mcpServerImage
    neo4jUri: neo4jUri
    neo4jDatabase: neo4jDatabase
    readOnlyMode: readOnlyMode
    allowedOrigins: allowedOrigins
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure region')
output location string = location

@description('Authentication mode')
output authMode string = 'bearer-token'

// Phase 1 Outputs
@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.id

// Phase 2 Outputs
@description('Key Vault name')
output keyVaultName string = keyVault.outputs.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.vaultUri

// Phase 3 Outputs
@description('Container Apps Environment ID')
output containerEnvironmentId string = containerEnvironment.outputs.id

@description('Container Apps Environment default domain')
output containerEnvironmentDefaultDomain string = containerEnvironment.outputs.defaultDomain

// Phase 4 Outputs (conditional - only when container app is deployed)
@description('Container App name')
output containerAppName string = deployContainerApp ? containerApp.outputs.name : ''

@description('Container App FQDN')
output containerAppFqdn string = deployContainerApp ? containerApp.outputs.fqdn : ''

@description('Container App URL')
output containerAppUrl string = deployContainerApp ? containerApp.outputs.url : ''

@description('MCP endpoint URL')
output mcpEndpoint string = deployContainerApp ? '${containerApp.outputs.url}/mcp' : ''

@description('MCP Server container image deployed')
output mcpServerImage string = mcpServerImage

@description('Whether container app was deployed')
output containerAppDeployed bool = deployContainerApp
