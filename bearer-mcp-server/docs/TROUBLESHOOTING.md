# Troubleshooting Guide

This guide helps diagnose and resolve common issues with bearer token authentication.

## Quick Diagnostic Checklist

1. Is the MCP server running?
2. Is the Neo4j database accessible?
3. Is the token valid and not expired?
4. Is the token audience correct?
5. Is Neo4j configured for OIDC?

---

## Authentication Errors

### 401 Unauthorized - Missing Token

**Symptom**: Request rejected with "Missing API key" or "Unauthorized"

**Causes**:
- No Authorization header in request
- Malformed Authorization header

**Solution**:
```bash
# Correct format
curl -H "Authorization: Bearer YOUR_TOKEN" https://your-endpoint/mcp

# NOT these:
curl -H "Authorization: YOUR_TOKEN"           # Missing "Bearer" prefix
curl -H "Bearer: YOUR_TOKEN"                  # Wrong header name
```

### 401 Unauthorized - Invalid Token

**Symptom**: "Invalid token" or "Token validation failed"

**Causes**:
- Token is expired
- Token was issued for wrong audience
- Token signature cannot be verified

**Diagnostic steps**:

1. **Decode the token** (at [jwt.io](https://jwt.io)):
   ```bash
   echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .
   ```

2. **Check expiration**:
   ```json
   {
     "exp": 1705123456  // Unix timestamp - is this in the future?
   }
   ```

3. **Check audience**:
   ```json
   {
     "aud": "api://your-app-id"  // Must match Neo4j's configured audience
   }
   ```

4. **Check issuer**:
   ```json
   {
     "iss": "https://login.microsoftonline.com/tenant-id/v2.0"
   }
   ```

### 403 Forbidden - Insufficient Permissions

**Symptom**: "Access denied" or "Insufficient privileges"

**Causes**:
- Token is valid but user lacks Neo4j role
- Group-to-role mapping not configured
- User not in required IdP group

**Solution**:
1. Check token's group claims
2. Verify Neo4j role mapping in `neo4j.conf`
3. Add user to appropriate IdP group

---

## Neo4j Connection Errors

### "Failed to connect to Neo4j"

**Causes**:
- Wrong NEO4J_URI
- Neo4j not accessible from Azure
- SSL/TLS issues

**Diagnostic steps**:

1. **Test connectivity from container**:
   ```bash
   # Get container logs
   az containerapp logs show \
     --name your-app-name \
     --resource-group your-rg \
     --container mcp-server \
     --tail 100
   ```

2. **Check NEO4J_URI format**:
   ```
   # Correct formats:
   neo4j+s://xxx.databases.neo4j.io    # Aura (encrypted)
   neo4j://localhost:7687              # Local (unencrypted)
   neo4j+ssc://host:7687               # Self-signed cert
   ```

### "Authentication failed at Neo4j level"

**Causes**:
- Neo4j not configured for OIDC
- JWKS endpoint not accessible from Neo4j
- Audience mismatch

**Solution**:

1. **Check Neo4j security log**:
   ```
   tail -f /var/log/neo4j/security.log
   ```

2. **Verify Neo4j OIDC config**:
   ```properties
   # In neo4j.conf
   dbms.security.authentication_providers=oidc-azure,native
   dbms.security.oidc.azure.well_known_discovery_uri=https://...
   dbms.security.oidc.azure.audience=YOUR_APP_ID
   ```

3. **Test JWKS endpoint from Neo4j**:
   ```bash
   curl https://login.microsoftonline.com/tenant-id/discovery/v2.0/keys
   ```

---

## Token Acquisition Errors

### Azure Entra ID: "AADSTS700016"

**Message**: "Application not found in directory"

**Solution**:
- Verify client_id is correct
- Check app is in correct tenant
- Ensure app registration is not deleted

### Azure Entra ID: "AADSTS7000215"

**Message**: "Invalid client secret"

**Solution**:
- Regenerate client secret
- Check for leading/trailing whitespace
- Verify secret hasn't expired

### Azure Entra ID: "AADSTS50126"

**Message**: "Invalid username or password"

**Solution**:
- This error shouldn't occur for client credentials flow
- Verify you're using correct grant type

### Okta: "invalid_client"

**Solution**:
- Check client ID and secret
- Verify application is active
- Check client authentication method

---

## Container App Issues

### Container Keeps Restarting

**Diagnostic**:
```bash
# Check container status
az containerapp show \
  --name your-app \
  --resource-group your-rg \
  --query "properties.runningStatus"

# Check logs
az containerapp logs show \
  --name your-app \
  --resource-group your-rg \
  --container mcp-server
```

**Common causes**:
- Invalid NEO4J_URI causing startup failure
- Memory limits too low
- Health probe failing

### Health Probe Failing

**Symptom**: Container restarts repeatedly, "Unhealthy" status

**Diagnostic**:
```bash
# Check probe configuration
az containerapp show \
  --name your-app \
  --resource-group your-rg \
  --query "properties.template.containers[0].probes"
```

**Solution**:
- Increase `initialDelaySeconds` if startup is slow
- Verify port 8000 is correct
- Check container logs for startup errors

### Cannot Pull Image

**Symptom**: "ImagePullBackOff" or "ErrImagePull"

**Diagnostic**:
```bash
# Verify the image exists on Docker Hub
docker pull docker.io/mcp/neo4j:latest

# Check Container App configuration
az containerapp show --name your-app --resource-group your-rg \
  --query "properties.template.containers[0].image"
```

**Solution**:
- Verify image name and tag (default: `docker.io/mcp/neo4j:latest`)
- Check `MCP_SERVER_IMAGE` in `.env` if using a custom image
- Ensure the Container App has outbound internet access to Docker Hub

---

## Debugging Commands

### View Container Logs

```bash
# Real-time logs
az containerapp logs show \
  --name your-app \
  --resource-group your-rg \
  --container mcp-server \
  --follow

# Historical logs (via Log Analytics)
az monitor log-analytics query \
  --workspace your-workspace \
  --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'your-app' | top 100 by TimeGenerated"
```

### Test Endpoint Directly

```bash
# Test without auth (should return 401)
curl -v https://your-endpoint.azurecontainerapps.io/mcp

# Test with auth
curl -v -X POST https://your-endpoint.azurecontainerapps.io/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

### Decode JWT Token

```bash
# Using jq
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .

# Check expiration
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp | todate'
```

### Check Azure Resources

```bash
# List all resources in resource group
az resource list --resource-group your-rg --output table

# Check Container App status
az containerapp show --name your-app --resource-group your-rg --output table

# Check Key Vault
az keyvault show --name your-kv --output table
```

---

## Common Misconfigurations

### Wrong Audience in Neo4j

**Problem**: Neo4j expects `api://app-id` but token has `app-id`

**Solution**: Match exactly what your IdP puts in the token's `aud` claim

### Missing Group Claims

**Problem**: Token doesn't contain group claims for role mapping

**For Azure Entra ID**:
1. Go to App Registration > Token configuration
2. Add groups claim
3. Choose appropriate group type

**For Okta**:
1. Go to Applications > Your App > Sign On
2. Edit OpenID Connect ID Token
3. Add groups claim

### Clock Skew

**Problem**: Token appears expired but should be valid

**Solution**: Ensure all systems have synchronized time (NTP)

---

## Getting Help

1. **Check logs first**: Container logs often contain detailed error messages
2. **Decode the token**: Many issues are visible in token claims
3. **Test incrementally**: Verify each component (IdP, MCP server, Neo4j) separately
4. **Enable debug logging**: Set `NEO4J_LOG_LEVEL=debug` for more details
