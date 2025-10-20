
import os, logging
import azure.functions as func
from azure.storage.blob import BlobServiceClient
from .lib.extract import extract_text
from .lib.indexer import index_chunks

ST_CONN = os.environ["DATA_STORAGE_CONNECTION"]
DOCS_CONTAINER = os.getenv("DOCS_CONTAINER", "docs")

blob_svc = BlobServiceClient.from_connection_string(ST_CONN)

app = func.FunctionApp()

@app.function_name(name="ingest")
@app.blob_trigger(arg_name="blob", path=f"{DOCS_CONTAINER}/{{name}}", connection="DATA_STORAGE_CONNECTION")
def run(blob: func.InputStream):
    name = blob.name
    logging.info(f"[ingest] Processing: {name} ({blob.length} bytes)")

    # Expect path: docs/<customerId>/<serviceArea>/raw/<filename>
    try:
        _, customerId, serviceArea, folder, filename = name.split('/', 4)
    except ValueError:
        logging.warning(f"[ingest] Skipping unexpected path: {name}")
        return

    if folder != 'raw':
        logging.info(f"[ingest] Non-raw path, skipping: {name}")
        return

    text = extract_text(blob.read(), filename)
    if not text or len(text.strip()) == 0:
        logging.warning("[ingest] No text extracted")
        return

    meta = {
        "customerId": customerId,
        "serviceArea": serviceArea,
        "title": os.path.splitext(filename)[0],
        "sourceUrl": name,
        "docType": "Other"
    }

    count = index_chunks(meta, text)
    logging.info(f"[ingest] Indexed {count} chunks for {name}")
