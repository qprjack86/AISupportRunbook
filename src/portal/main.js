
import axios from 'axios';

const apiPyBase = import.meta.env.VITE_API_PY_BASE || '';

const el = document.getElementById('app');

el.innerHTML = `
  <h1>Runbook RAG MVP — DOCX</h1>
  <section>
    <label>Customer ID <input id="cust" value="ppf-group"/></label>
    <label>Service Area
      <select id="svc">
        <option>ASR</option>
        <option selected>AVD</option>
        <option>LandingZone</option>
      </select>
    </label>
    <label>File <input id="file" type="file"/></label>
    <button id="upload">Upload</button>
  </section>
  <section>
    <button id="generate">Generate Runbook (DOCX)</button>
  </section>
  <pre id="out"></pre>
`;

async function upload() {
  const cust = document.getElementById('cust').value;
  const svc = document.getElementById('svc').value;
  const fileEl = document.getElementById('file');
  const file = fileEl.files[0];
  if (!file) return alert('Pick a file');

  const sasRes = await axios.post(`${apiPyBase}/api/sas`, { customerId: cust, serviceArea: svc, fileName: file.name });
  const url = sasRes.data.uploadUrl;
  await axios.put(url, file, { headers: { 'x-ms-blob-type': 'BlockBlob' } });
  document.getElementById('out').textContent = `Uploaded to ${url.split('?')[0]}`;
}

async function generate() {
  const cust = document.getElementById('cust').value;
  const svc = document.getElementById('svc').value;
  const res = await axios.post(`${apiPyBase}/api/generate`, { customerId: cust, serviceArea: svc });
  const docxPath = res.data.docxPath;
  document.getElementById('out').textContent = JSON.stringify({ docxPath }, null, 2);
}

document.getElementById('upload').onclick = upload;
document.getElementById('generate').onclick = generate;
