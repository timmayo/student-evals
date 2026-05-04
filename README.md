# Student Evals

A lightweight feedback app where students leave course reviews visible to future students. Built on GitHub Pages (frontend) + Azure Functions + Azure Table Storage + Azure Key Vault.

---

## Architecture

```
GitHub Pages  (index.html)
      │
      │  GET  /api/entries   →  returns all evals (public, no token required)
      │  POST /api/entry     →  submits a new eval (requires class access code)
      ▼
Azure Function App  (PowerShell runtime)
      │
      ├── Azure Table Storage  →  stores eval entries  (table: studentevals)
      └── Azure Key Vault      →  stores secrets
              ├── student-evals-token   (shared class access code)
              └── storage-account-key  (Table Storage auth key)
```

The Function App authenticates to Key Vault using a **system-assigned Managed Identity** — no secrets are stored in code or app settings.

---

## Setup

### 1. Azure Table Storage

```bash
# Create a storage account (if you don't already have one)
az storage account create \
  --name <STORAGE_ACCOUNT_NAME> \
  --resource-group <RG> \
  --sku Standard_LRS \
  --location eastus

# Create the table
az storage table create \
  --name studentevals \
  --account-name <STORAGE_ACCOUNT_NAME>
```

### 2. Azure Function App

```bash
# Create the Function App (PowerShell runtime)
az functionapp create \
  --resource-group <RG> \
  --consumption-plan-location eastus \
  --runtime powershell \
  --runtime-version 7.4 \
  --functions-version 4 \
  --name <FUNCTION_APP_NAME> \
  --storage-account <STORAGE_ACCOUNT_NAME>

# Enable system-assigned Managed Identity
az functionapp identity assign \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RG>

# Note the principalId from the output — you'll need it in step 3
```

Set the two required app settings:

```bash
az functionapp config appsettings set \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RG> \
  --settings \
    STORAGE_ACCOUNT_NAME=<STORAGE_ACCOUNT_NAME> \
    KEY_VAULT_NAME=<KEY_VAULT_NAME>
```

### 3. Azure Key Vault

```bash
# Create Key Vault
az keyvault create \
  --name <KEY_VAULT_NAME> \
  --resource-group <RG> \
  --location eastus

# Grant the Function App's Managed Identity access to read secrets
az keyvault set-policy \
  --name <KEY_VAULT_NAME> \
  --object-id <MANAGED_IDENTITY_PRINCIPAL_ID> \
  --secret-permissions get

# Store the class access code (choose any token you like)
az keyvault secret set \
  --vault-name <KEY_VAULT_NAME> \
  --name student-evals-token \
  --value "<YOUR_CLASS_ACCESS_CODE>"

# Store the storage account key
STORAGE_KEY=$(az storage account keys list \
  --account-name <STORAGE_ACCOUNT_NAME> \
  --query "[0].value" -o tsv)

az keyvault secret set \
  --vault-name <KEY_VAULT_NAME> \
  --name storage-account-key \
  --value "$STORAGE_KEY"
```

### 4. Enable CORS on the Function App

```bash
az functionapp cors add \
  --name <FUNCTION_APP_NAME> \
  --resource-group <RG> \
  --allowed-origins "https://<YOUR_GITHUB_USERNAME>.github.io"
```

### 5. Deploy the Function App

```bash
cd api
func azure functionapp publish <FUNCTION_APP_NAME>
```

### 6. Update index.html

Open `index.html` and replace the placeholder with your deployed Function App URL:

```js
const API_BASE = 'https://<FUNCTION_APP_NAME>.azurewebsites.net/api';
```

### 7. Push to GitHub Pages

```bash
git init
git add .
git commit -m "Initial Student Evals deploy"
git branch -M main
git remote add origin https://github.com/timmayo/student-evals.git
git push -u origin main
```

Then in your GitHub repo: **Settings → Pages → Source → Deploy from branch → main / root**.

---

## Giving students the access code

Share the value you stored in `student-evals-token` with students at the end of each course session. They enter it in the "Class Access Code" field before submitting. Reading evals requires no code.

---

## File structure

```
student-evals/
├── index.html               # GitHub Pages frontend
├── .gitignore
├── README.md
└── api/
    ├── host.json
    ├── requirements.psd1
    ├── entries/
    │   ├── function.json    # GET /api/entries
    │   └── run.ps1
    └── entry/
        ├── function.json    # POST /api/entry
        └── run.ps1
```
