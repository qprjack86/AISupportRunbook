
import os, hashlib
from azure.search.documents import SearchClient
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

SEARCH_ENDPOINT = os.environ["SEARCH_ENDPOINT"]
SEARCH_INDEX = os.environ.get("SEARCH_INDEX", "support-docs")
AOAI_ENDPOINT = os.environ["AOAI_ENDPOINT"]
EMBED_DEPLOYMENT = os.environ.get("EMBED_DEPLOYMENT", "text-embedding-3-small")

search = SearchClient(endpoint=SEARCH_ENDPOINT, index_name=SEARCH_INDEX, credential=DefaultAzureCredential())
cred = DefaultAzureCredential()
provider = get_bearer_token_provider(cred, "https://cognitiveservices.azure.com/.default")
aoai = AzureOpenAI(azure_endpoint=AOAI_ENDPOINT, api_version="2024-06-01", azure_ad_token_provider=provider)

def chunk_text(text: str, target_words=350):
    paras = [p.strip() for p in text.split('') if p.strip()]
    chunk, wc = [], 0
    for p in paras:
        w = len(p.split())
        if wc + w > target_words and chunk:
            yield "".join(chunk)
            chunk, wc = [], 0
        chunk.append(p)
        wc += w
    if chunk:
        yield "".join(chunk)


def embed(texts: list[str]) -> list[list[float]]:
    resp = aoai.embeddings.create(input=texts, model=EMBED_DEPLOYMENT)
    return [d.embedding for d in resp.data]


def index_chunks(meta: dict, text: str) -> int:
    chunks = list(chunk_text(text))
    if not chunks:
        return 0
    vectors = embed(chunks)
    docs = []
    for i, (c, v) in enumerate(zip(chunks, vectors)):
        docs.append({
            "id": f"{meta['customerId']}-{meta['serviceArea']}-{meta['title']}-{i}",
            "customerId": meta['customerId'],
            "serviceArea": meta['serviceArea'],
            "title": meta['title'],
            "sourceUrl": meta['sourceUrl'],
            "docType": meta.get('docType', 'Other'),
            "text": c,
            "vector": v,
            "chunkId": i,
            "hash": hashlib.sha256(c.encode('utf-8')).hexdigest()
        })
    search.upload_documents(docs)
    return len(docs)
