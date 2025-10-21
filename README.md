
# Runbook RAG MVP (Option B) — UK South (Static Website + DOCX)

Azure-native Retrieval Augmented Generation MVP to generate all-levels support runbooks from documents stored in **Azure Blob Storage**.  
**Primary output:** Word **.docx** (plus optional PDF).  
Pilot: **PPF Group** across **ASR, AVD, LandingZone**.

This variant uses **Storage Static Website** (not Static Web Apps) so everything runs in **UK South**.

## Quick start (with `azd`)

```bash
azd auth login
az account set --subscription "<SUBSCRIPTION_ID>"

azd env new ppf-mvp-uksouth
azd up        # provisions all Azure resources EXCEPT the portal site deploy

# build & upload portal to $web
./scripts/deploy-portal.sh $(azd env get-values | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2)
```

## What gets deployed
- Storage (containers: `docs`, `runbooks`, and **$web** for the portal)
- Blob Static Website enabled (serves the portal)
- Two Function Apps (Python pipeline + Node converters) with Managed Identity
- Azure AI Search (vector enabled)
- Azure OpenAI (deployments: `gpt-4o-mini`, `text-embedding-3-small`)
- Key Vault + App Insights

## Outputs
- `runbooks/<customer>/<service>/<timestamp>/runbook.docx` (primary)
- `runbooks/.../runbook.md` (source)
- `runbooks/.../runbook.pdf` (optional)

## Portal configuration
Create `src/portal/.env`:
```ini
VITE_API_PY_BASE=https://<func-py-name>.azurewebsites.net
VITE_API_NODE_BASE=https://<func-node-name>.azurewebsites.net
VITE_PY_CODE=<function key>
VITE_NODE_CODE=<function key>
```

Then deploy the portal with `scripts/deploy-portal.sh` (builds and uploads to `$web`).

## Notes
- AOAI auth uses Managed Identity; no API keys stored.
- If model deployments fail in your region/tenant, adjust names/region in `infra/main.bicep`.
- CORS for Function Apps is configured to allow the static website origin.
