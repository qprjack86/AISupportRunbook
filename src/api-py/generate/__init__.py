
import os, json, datetime
import azure.functions as func
from azure.search.documents import SearchClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI
from azure.storage.blob import BlobClient

SEARCH_ENDPOINT = os.environ["SEARCH_ENDPOINT"]
SEARCH_INDEX = os.environ.get("SEARCH_INDEX", "support-docs")
AOAI_ENDPOINT = os.environ["AOAI_ENDPOINT"]
AOAI_DEPLOYMENT = os.environ.get("AOAI_DEPLOYMENT", "gpt-4o-mini")
ST_CONN = os.environ["DATA_STORAGE_CONNECTION"]
RUNBOOKS_CONTAINER = os.getenv("RUNBOOKS_CONTAINER", "runbooks")

search = SearchClient(SEARCH_ENDPOINT, SEARCH_INDEX, DefaultAzureCredential())
cred = DefaultAzureCredential()
_token = get_bearer_token_provider(cred, "https://cognitiveservices.azure.com/.default")
aoai = AzureOpenAI(azure_endpoint=AOAI_ENDPOINT, api_version="2024-06-01", azure_ad_token_provider=_token)

SYSTEM_PROMPT = (
    "You are an expert Azure support runbook writer. Produce a single comprehensive runbook suitable for all levels "
    "in managed services without L1/L2/L3 labels. Use British English; be concise, operational, accurate. "
    "Use ONLY provided sources and add a "Gaps & Assumptions" section when information is missing. "
    "Include citations as blob paths."
)

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.function_name(name="generate")
@app.route(route="generate", methods=["POST"])
def run(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    cust = body.get("customerId")
    svc = body.get("serviceArea")
    query = body.get("query", f"{svc} runbook")
    if not cust or not svc:
        return func.HttpResponse("customerId and serviceArea required", status_code=400)

    results = search.search(search_text=query, filter=f"customerId eq '{cust}' and serviceArea eq '{svc}'", top=14)
    chunks = [{"text": r["text"], "source": r.get("sourceUrl") } for r in results]

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": json.dumps({"customerId": cust, "serviceArea": svc, "sources": chunks})}
    ]
    resp = aoai.chat.completions.create(model=AOAI_DEPLOYMENT, messages=messages, temperature=0.2)
    md = resp.choices[0].message.content

    stamp = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    path = f"{cust}/{svc}/{stamp}/runbook.md"
    blob = BlobClient.from_connection_string(ST_CONN, container_name=RUNBOOKS_CONTAINER, blob_name=path)
    blob.upload_blob(md.encode('utf-8'), overwrite=True)

    return func.HttpResponse(json.dumps({"status": "ok", "markdownPath": f"{RUNBOOKS_CONTAINER}/{path}"}), mimetype="application/json")
