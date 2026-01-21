// =============================================================================
// Container App Module - Bearer Token Authentication
// Creates an Azure Container App for the Neo4j MCP Server with native bearer
// token authentication. Single container deployment - no proxy required.
//
// Architecture:
// - Single MCP Server container (port 8000, external)
// - Bearer tokens passed through to Neo4j for SSO/OIDC validation
// - No static credentials - authentication per-request via JWT
//
// Traffic flow:
// Internet -> Ingress (443) -> MCP Server (8000) -> Neo4j (with bearer auth)
//
// Authentication:
// - Clients obtain JWT tokens from their identity provider (Entra ID, Okta, etc.)
// - Clients send requests with Authorization: Bearer <token>
// - MCP Server extracts token and passes to Neo4j via BearerAuth
// - Neo4j validates token against configured OIDC provider
//
// Requirements:
// - Neo4j Enterprise Edition with OIDC configured, OR
// - Neo4j Aura Enterprise with SSO enabled
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

@description('Neo4j MCP Server container image')
param mcpServerImage string

@description('Container Registry login server')
param containerRegistryLoginServer string

@description('Neo4j database connection URI')
@secure()
param neo4jUri string

@description('Neo4j database name')
param neo4jDatabase string = 'neo4j'

@description('Enable read-only mode (disables write-cypher tool)')
param readOnlyMode bool = true

@description('Allowed CORS origins (comma-separated, or * for all, empty to disable)')
param allowedOrigins string = ''

// =============================================================================
// Container App Configuration
// =============================================================================

// Use latest stable API version (2025-07-01)
// Reference: https://learn.microsoft.com/en-us/azure/templates/microsoft.app/2025-07-01/containerapps
resource containerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: name
  location: location
  tags: tags
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
      // No secrets from Key Vault - bearer mode uses per-request authentication
      // Neo4j URI passed as environment variable (not a credential)
      secrets: []
      // External ingress configuration - routes directly to MCP server
      // No proxy - MCP server handles authentication natively
      ingress: {
        external: true
        targetPort: 8000  // MCP server HTTP port
        transport: 'http'
        allowInsecure: false  // HTTPS only
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        // CORS configuration for web-based clients
        corsPolicy: !empty(allowedOrigins) ? {
          allowedOrigins: allowedOrigins == '*' ? ['*'] : split(allowedOrigins, ',')
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['Content-Type', 'Authorization']
          maxAge: 86400  // 24 hours
        } : null
      }
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        // =======================================================================
        // Neo4j MCP Server Container
        // Single container with bearer token authentication
        // Handles MCP protocol requests and forwards bearer tokens to Neo4j
        // =======================================================================
        {
          name: 'mcp-server'
          image: mcpServerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            // Neo4j connection URI (not a credential, just connection info)
            {
              name: 'NEO4J_URI'
              value: neo4jUri
            }
            {
              name: 'NEO4J_DATABASE'
              value: neo4jDatabase
            }
            // HTTP transport mode - enables per-request authentication
            // In HTTP mode, credentials come from request headers, not env vars
            {
              name: 'NEO4J_MCP_TRANSPORT'
              value: 'http'
            }
            {
              name: 'NEO4J_MCP_HTTP_HOST'
              value: '0.0.0.0'  // Listen on all interfaces (for external ingress)
            }
            {
              name: 'NEO4J_MCP_HTTP_PORT'
              value: '8000'
            }
            // CORS configuration (if specified)
            {
              name: 'NEO4J_MCP_HTTP_ALLOWED_ORIGINS'
              value: allowedOrigins
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
            // Read-only mode configuration
            {
              name: 'NEO4J_READ_ONLY'
              value: readOnlyMode ? 'true' : 'false'
            }
            // Disable telemetry for cleaner logs (optional)
            {
              name: 'NEO4J_TELEMETRY'
              value: 'false'
            }
          ]
          // Health probes for the MCP server
          // Note: MCP server's /mcp endpoint handles JSON-RPC, not standard HTTP health checks
          // Using TCP probe as the MCP server doesn't have a dedicated health endpoint
          probes: [
            {
              type: 'Liveness'
              tcpSocket: {
                port: 8000
              }
              initialDelaySeconds: 5
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              tcpSocket: {
                port: 8000
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Startup'
              tcpSocket: {
                port: 8000
              }
              initialDelaySeconds: 2
              periodSeconds: 5
              failureThreshold: 10  // Allow up to 50 seconds for startup
            }
          ]
        }
      ]
      // Fixed scale - exactly 1 replica for consistent behavior
      // For production, consider autoscaling based on HTTP requests
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
