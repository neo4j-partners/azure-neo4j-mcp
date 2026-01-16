// =============================================================================
// Container App Module
// Creates an Azure Container App for the Neo4j MCP Server with Nginx auth proxy.
//
// Architecture:
// - Nginx sidecar (port 8080): Validates API keys, proxies to MCP server
// - MCP Server (port 8000): Handles MCP protocol requests to Neo4j
//
// Traffic flow:
// Internet -> Ingress (443) -> Nginx (8080) -> MCP Server (8000) -> Neo4j
//
// Configures:
// - Fixed 1 replica for consistent demo behavior
// - Managed identity for ACR image pull and Key Vault access
// - Key Vault references for all sensitive environment variables
// - External HTTPS ingress through Nginx auth proxy
// - Resource limits optimized for demo workloads
// =============================================================================

@description('Name of the Container App')
@minLength(2)
@maxLength(32)
param name string

@description('Azure region for the Container App')
param location string

@description('Tags to apply to the Container App')
param tags object = {}

@description('Resource ID of the Container Apps Environment')
param containerAppsEnvironmentId string

@description('Resource ID of the user-assigned managed identity')
param managedIdentityId string

@description('Neo4j MCP Server container image (e.g., myacr.azurecr.io/neo4j-mcp-server:latest)')
param mcpServerImage string

@description('Nginx auth proxy container image (e.g., myacr.azurecr.io/mcp-auth-proxy:latest)')
param authProxyImage string

@description('Container Registry login server (e.g., myacr.azurecr.io)')
param containerRegistryLoginServer string

@description('Key Vault name for secret references')
param keyVaultName string

// =============================================================================
// Container App Configuration
// =============================================================================

// Use latest stable API version (2025-01-01)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.app/containerapps
resource containerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: name
  location: location
  tags: tags
  // Assign user-assigned managed identity for ACR pull and Key Vault access
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      // ACR authentication using managed identity
      registries: [
        {
          server: containerRegistryLoginServer
          identity: managedIdentityId
        }
      ]
      // Secrets from Key Vault using managed identity
      secrets: [
        {
          name: 'neo4j-uri'
          keyVaultUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/neo4j-uri'
          identity: managedIdentityId
        }
        {
          name: 'neo4j-username'
          keyVaultUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/neo4j-username'
          identity: managedIdentityId
        }
        {
          name: 'neo4j-password'
          keyVaultUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/neo4j-password'
          identity: managedIdentityId
        }
        {
          name: 'neo4j-database'
          keyVaultUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/neo4j-database'
          identity: managedIdentityId
        }
        {
          name: 'mcp-api-key'
          keyVaultUrl: 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/secrets/mcp-api-key'
          identity: managedIdentityId
        }
      ]
      // External ingress configuration - routes to Nginx auth proxy
      ingress: {
        external: true
        targetPort: 8080  // Nginx auth proxy port
        transport: 'http'
        allowInsecure: false  // HTTPS only
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      // Active revisions mode - single revision for simplicity
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        // =======================================================================
        // Nginx Auth Proxy Container
        // Validates API keys and proxies authenticated requests to MCP server
        // =======================================================================
        {
          name: 'auth-proxy'
          image: authProxyImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            // API key for client authentication
            {
              name: 'MCP_API_KEY'
              secretRef: 'mcp-api-key'
            }
            // Neo4j credentials for Basic Auth to MCP server
            {
              name: 'NEO4J_USERNAME'
              secretRef: 'neo4j-username'
            }
            {
              name: 'NEO4J_PASSWORD'
              secretRef: 'neo4j-password'
            }
          ]
          // Health probes using Nginx's HTTP health endpoints
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 15
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
        // =======================================================================
        // Neo4j MCP Server Container
        // Handles MCP protocol requests and communicates with Neo4j database
        // =======================================================================
        {
          name: 'mcp-server'
          image: mcpServerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            // Neo4j connection URI (from Key Vault)
            // Note: Username/password are NOT passed here so MCP server skips startup
            // verification in HTTP mode. Credentials come from per-request Basic Auth
            // headers injected by the nginx proxy.
            {
              name: 'NEO4J_URI'
              secretRef: 'neo4j-uri'
            }
            {
              name: 'NEO4J_DATABASE'
              secretRef: 'neo4j-database'
            }
            // Transport configuration - use HTTP mode
            {
              name: 'NEO4J_MCP_TRANSPORT'
              value: 'http'
            }
            {
              name: 'NEO4J_MCP_HTTP_HOST'
              value: '127.0.0.1'  // Listen only on localhost (Nginx proxies to this)
            }
            {
              name: 'NEO4J_MCP_HTTP_PORT'
              value: '8000'
            }
            // Logging configuration for containerized environment
            {
              name: 'NEO4J_LOG_FORMAT'
              value: 'json'  // Structured logs for Log Analytics
            }
            {
              name: 'NEO4J_LOG_LEVEL'
              value: 'info'
            }
          ]
          // TCP probe for MCP server (no HTTP health endpoint available)
          probes: [
            {
              type: 'Liveness'
              tcpSocket: {
                port: 8000
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              tcpSocket: {
                port: 8000
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      // Fixed scale - exactly 1 replica for demo consistency
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the Container App')
output id string = containerApp.id

@description('Name of the Container App')
output name string = containerApp.name

@description('FQDN of the Container App')
output fqdn string = containerApp.properties.configuration.ingress.fqdn

@description('URL of the Container App')
output url string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Latest revision name')
output latestRevisionName string = containerApp.properties.latestRevisionName
