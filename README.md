
# Runbook RAG MVP (Option B) — UK South

Azure-native Retrieval Augmented Generation MVP to generate all-levels support runbooks from documents stored in **Azure Blob Storage**.  
**Output: Word (.docx) only**.

Pilot: **PPF Group** across **ASR, AVD, LandingZone**.

## Quick start (with `azd`)

```bash
# 1) Prerequisites
azd auth login
az account set --subscription "<SUBSCRIPTION_ID>"

# 2) Initialise environment
azd env new ppf-mvp-uksouth

# 3) Deploy infra + apps
azd up
```

> Region is pinned to **UK South** by default. Adjust in `infra/main.bicep` if needed.

## What gets deployed
- Storage (containers: `docs`, `runbooks`)
- Python Azure Functions (blob ingest + HTTP generate + SAS), Managed Identity
- Azure AI Search (vector enabled)
- Azure OpenAI (deployments: `gpt-4o-mini`, `text-embedding-3-small`)
- Static Web App (portal)
- Key Vault + App Insights

## Portal dev
```bash
cd src/portal
npm install
npm run dev
```

## Flow (DOCX only)
1. Portal requests a **SAS** for `docs/{customerId}/{serviceArea}/raw/`
2. Browser uploads directly to Blob (no duplicates)
3. **Blob Trigger** extracts → chunks → embeds → indexes in AI Search
4. Click **Generate Runbook** → Function retrieves chunks → calls Azure OpenAI → builds **runbook.docx** → saves to Blob

## Notes
- Azure OpenAI model names/versions vary by region/tenant; adjust in `infra/main.bicep` if deployments fail.
- Search index can be created via `scripts/postprovision.ps1`.
