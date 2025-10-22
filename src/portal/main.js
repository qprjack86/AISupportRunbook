
import axios from 'axios';

const apiPyBase = import.meta.env.VITE_API_PY_BASE || '';
const apiNodeBase = import.meta.env.VITE_API_NODE_BASE || '';
const PY_CODE = import.meta.env.VITE_PY_CODE || '';
const NODE_CODE = import.meta.env.VITE_NODE_CODE || '';

const el = document.getElementById('app');

el.innerHTML = `
   <h1>Runbook RAG MVP</h1>

   <!-- Prompt Enhancement Section -->
   <section class="enhance-section">
     <h2>Enhance Prompt</h2>
     <div class="enhance-container">
       <label>Original Prompt</label>
       <textarea id="original-prompt" placeholder="Enter your prompt here..." rows="4"></textarea>
       <button id="enhance-btn">Enhance Prompt</button>
       <label>Enhanced Prompt</label>
       <textarea id="enhanced-prompt" placeholder="Enhanced prompt will appear here..." rows="4" readonly></textarea>
     </div>
   </section>

   <hr>

   <!-- Existing Upload Section -->
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
     <button id="generate">Generate Runbook</button>
   </section>
   <pre id="out"></pre>
 `;

async function upload() {
  const cust = document.getElementById('cust').value;
  const svc = document.getElementById('svc').value;
  const fileEl = document.getElementById('file');
  const file = fileEl.files[0];
  if (!file) return alert('Pick a file');

  const sasRes = await axios.post(`${apiPyBase}/api/sas?code=${PY_CODE}`, { customerId: cust, serviceArea: svc, fileName: file.name });
  const url = sasRes.data.uploadUrl;
  await axios.put(url, file, { headers: { 'x-ms-blob-type': 'BlockBlob' } });
  document.getElementById('out').textContent = `Uploaded to ${url.split('?')[0]}`;
}

async function generate() {
  const cust = document.getElementById('cust').value;
  const svc = document.getElementById('svc').value;
  const res = await axios.post(`${apiPyBase}/api/generate?code=${PY_CODE}`, { customerId: cust, serviceArea: svc });
  const mdPath = res.data.markdownPath;

  // DOCX (primary)
  const docxRes = await axios.post(`${apiNodeBase}/api/md2docx?code=${NODE_CODE}`, { markdownPath: mdPath.replace('runbooks/', '') });
  const docxPath = `runbooks/${docxRes.data.docxPath}`;

  // Optional PDF
  const pdfRes = await axios.post(`${apiNodeBase}/api/md2pdf?code=${NODE_CODE}`, { markdownPath: mdPath.replace('runbooks/', '') });
  const pdfPath = `runbooks/${pdfRes.data.pdfPath}`;

  document.getElementById('out').textContent = JSON.stringify({ mdPath, docxPath, pdfPath }, null, 2);
}

async function enhancePrompt() {
   const originalPrompt = document.getElementById('original-prompt').value.trim();
   if (!originalPrompt) {
     alert('Please enter a prompt to enhance');
     return;
   }

   try {
     const response = await axios.post(`${apiPyBase}/api/enhance-prompt?code=${PY_CODE}`, {
       prompt: originalPrompt
     });

     document.getElementById('enhanced-prompt').value = response.data.enhancedPrompt;
   } catch (error) {
     console.error('Error enhancing prompt:', error);
     alert('Failed to enhance prompt. Please try again.');
   }
}

document.getElementById('upload').onclick = upload;
document.getElementById('generate').onclick = generate;
document.getElementById('enhance-btn').onclick = enhancePrompt;
