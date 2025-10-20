
import os, json, datetime
import azure.functions as func
from azure.storage.blob import generate_blob_sas, BlobSasPermissions, BlobServiceClient

ST_CONN = os.environ["DATA_STORAGE_CONNECTION"]
svc = BlobServiceClient.from_connection_string(ST_CONN)
DOCS_CONTAINER = os.getenv("DOCS_CONTAINER", "docs")

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

def _parse_conn_str(cs: str):
    parts = dict(p.split('=',1) for p in cs.split(';') if '=' in p)
    return parts.get('AccountName'), parts.get('AccountKey')

@app.function_name(name="sas")
@app.route(route="sas", methods=["POST"])
def run(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    cust = body.get("customerId")
    svcArea = body.get("serviceArea")
    fname = body.get("fileName")
    if not (cust and svcArea and fname):
        return func.HttpResponse("customerId, serviceArea, fileName required", status_code=400)

    account, key = _parse_conn_str(ST_CONN)
    if not account or not key:
        return func.HttpResponse("Storage connection string must include AccountName and AccountKey", status_code=500)

    sas = generate_blob_sas(account_name=account,
                            container_name=DOCS_CONTAINER,
                            blob_name=f"{cust}/{svcArea}/raw/{fname}",
                            account_key=key,
                            permission=BlobSasPermissions(create=True, write=True, add=True),
                            expiry=datetime.datetime.utcnow() + datetime.timedelta(minutes=30))

    url = f"https://{account}.blob.core.windows.net/{DOCS_CONTAINER}/{cust}/{svcArea}/raw/{fname}?{sas}"
    return func.HttpResponse(json.dumps({"uploadUrl": url}), mimetype="application/json")
