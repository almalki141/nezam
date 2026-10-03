'use strict';

const express = require('express');
const cors = require('cors');
const https = require('https');
const QRCode = require('qrcode');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {Client, LocalAuth} = require('whatsapp-web.js');

const PORT = Number(process.env.PORT || 8787);
const AUTH_TOKEN = String(process.env.AUTH_TOKEN || '');
const ALLOWED_ORIGIN = String(process.env.ALLOWED_ORIGIN || 'https://nezam.mrrsal.com');
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const JOBS_FILE = path.join(DATA_DIR, 'jobs.json');
if (!AUTH_TOKEN || AUTH_TOKEN.length < 24) throw new Error('AUTH_TOKEN must contain at least 24 characters');
fs.mkdirSync(DATA_DIR, {recursive: true});

const readJobs = () => { try { return JSON.parse(fs.readFileSync(JOBS_FILE, 'utf8')); } catch { return []; } };
const writeJobs = jobs => { const tmp=JOBS_FILE+'.tmp';fs.writeFileSync(tmp,JSON.stringify(jobs,null,2),{mode:0o600});fs.renameSync(tmp,JOBS_FILE); };
let jobs = readJobs();
let connected = false, qrData = '', waStatus = 'starting', lastError = '';

const client = new Client({
  authStrategy: new LocalAuth({dataPath: path.join(__dirname,'.wwebjs_auth')}),
  puppeteer: {headless: true,args:['--no-sandbox','--disable-setuid-sandbox','--disable-dev-shm-usage']}
});
client.on('qr', async raw => {qrData=await QRCode.toDataURL(raw,{margin:1,width:420});waStatus='qr';connected=false;});
client.on('ready', () => {connected=true;qrData='';waStatus='ready';lastError='';});
client.on('authenticated', () => {waStatus='authenticated';});
client.on('auth_failure', msg => {connected=false;waStatus='auth_failure';lastError=String(msg||'Authentication failed');});
client.on('disconnected', reason => {connected=false;waStatus='disconnected';lastError=String(reason||'Disconnected');setTimeout(()=>client.initialize().catch(()=>{}),5000);});
client.initialize().catch(error => {lastError=error.message;waStatus='error';});

const app = express();
app.disable('x-powered-by');
app.use(cors({origin(origin,cb){if(!origin||origin===ALLOWED_ORIGIN)return cb(null,true);cb(new Error('Origin not allowed'));},methods:['GET','POST']}));
app.use(express.json({limit:'512kb'}));
app.use((req,res,next)=>{const supplied=String(req.headers.authorization||'').replace(/^Bearer\s+/i,'');const a=Buffer.from(supplied),b=Buffer.from(AUTH_TOKEN);if(a.length!==b.length||!crypto.timingSafeEqual(a,b))return res.status(401).json({error:'Unauthorized'});next();});

const normalizePhone = value => {
  let n=String(value||'').replace(/\D/g,'');
  if(n.startsWith('05'))n='966'+n.slice(1);
  if(n.startsWith('5')&&n.length===9)n='966'+n;
  if(n.length<10||n.length>15)throw new Error('Invalid phone number');
  return n+'@c.us';
};
async function send(to,message){if(!connected)throw new Error('WhatsApp is not connected');if(!String(message||'').trim())throw new Error('Empty message');return client.sendMessage(normalizePhone(to),String(message).slice(0,4000));}

app.get('/health',(req,res)=>res.json({ok:true,connected,status:waStatus,lastError}));
app.get('/qr',(req,res)=>res.json({connected,status:waStatus,qr:qrData,lastError}));
app.post('/send',async(req,res)=>{try{const result=await send(req.body.to,req.body.message);res.json({ok:true,messageId:result.id&&result.id._serialized||'',sentAt:new Date().toISOString()});}catch(error){res.status(409).json({error:error.message});}});
app.post('/jobs/sync',(req,res)=>{const incoming=Array.isArray(req.body.jobs)?req.body.jobs:[];const prior=new Map(jobs.map(x=>[x.id,x]));jobs=incoming.filter(x=>x&&x.id&&x.to&&x.message&&x.scheduledAt).slice(0,2000).map(x=>{const old=prior.get(x.id)||{};return {...x,status:old.status||'pending',sentAt:old.sentAt||'',error:old.error||'',attempts:old.attempts||0,nextAttempt:old.nextAttempt||''}});writeJobs(jobs);res.json({ok:true,count:jobs.length});});
app.get('/jobs',(req,res)=>res.json({jobs:jobs.slice(-300)}));

let running=false;
async function runDueJobs(){if(running||!connected)return;running=true;try{for(const job of jobs){const now=new Date();if(job.status==='sent'||new Date(job.scheduledAt)>now||(job.nextAttempt&&new Date(job.nextAttempt)>now)||+(job.attempts||0)>=5)continue;try{await send(job.to,job.message);job.status='sent';job.sentAt=new Date().toISOString();job.error='';writeJobs(jobs);await new Promise(r=>setTimeout(r,2500));}catch(error){job.status='failed';job.attempts=+(job.attempts||0)+1;job.nextAttempt=new Date(Date.now()+Math.min(3600000,job.attempts*10*60000)).toISOString();job.error=error.message;writeJobs(jobs);}}}finally{running=false;}}
setInterval(runDueJobs,30000);

const tlsKey=process.env.TLS_KEY, tlsCert=process.env.TLS_CERT;
if(tlsKey&&tlsCert){https.createServer({key:fs.readFileSync(tlsKey),cert:fs.readFileSync(tlsCert)},app).listen(PORT,'127.0.0.1',()=>console.log(`Nezam WhatsApp bridge listening securely on localhost:${PORT}`));}
else app.listen(PORT,'127.0.0.1',()=>console.log(`Nezam WhatsApp bridge listening locally on ${PORT}`));

async function shutdown(){writeJobs(jobs);try{await client.destroy();}catch{}process.exit(0);}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
