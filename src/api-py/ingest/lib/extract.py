
import io
import fitz  # PyMuPDF

def extract_text(data: bytes, filename: str) -> str:
    name = filename.lower()
    if name.endswith('.pdf'):
        doc = fitz.open(stream=io.BytesIO(data), filetype='pdf')
        text = []
        for page in doc:
            text.append(page.get_text("text"))
        return "".join(text)
    elif name.endswith(('.md', '.txt', '.log')):
        return data.decode('utf-8', errors='ignore')
    else:
        try:
            return data.decode('utf-8', errors='ignore')
        except Exception:
            return ''
