$name = "dev-crossplane" # Name for the Crossplane deployment, can be customized
$subscriptionId = "your-subscription-id" # Replace with your Azure subscription ID

# Check if kubectl is installed
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "kubectl is not installed. Please install kubectl and try again."
    exit
}
# Check if Helm is installed
if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "Helm is not installed. Please install Helm and try again."
    exit
}

# Check if Azure CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Azure CLI is not installed. Please install Azure CLI and try again."
    exit
}

# Check if Azure Cli is Logged In
$loggedIn = az account show --query "id" -o tsv
if (-not $loggedIn) {
    Write-Host "You are not logged into Azure. Please log in using 'az login'."
    exit
} else {
    Write-Host "You are logged into Azure."
}

# Add crossplane helm repo
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

# Review the crossplane helm chart
helm install crossplane crossplane-stable/crossplane `
--dry-run --debug `
--namespace crossplane-system `
--create-namespace

Start-Sleep -Seconds 30

# Install crossplane
helm install crossplane `
crossplane-stable/crossplane `
--namespace crossplane-system `
--create-namespace

# Wait for crossplane to be ready
kubectl wait --for=condition=ready pod --all -n crossplane-system --timeout=120s

# Install the Azure Provider for Crossplane
kubectl apply -f azure-provider.yaml

# Wait for the Azure provider to be ready
kubectl wait --for=condition=ready provider.azure.upbound.io/crossplane-provider-azure --timeout=120s

# Install the Azure provider Config for Crossplane
kubectl apply -f azure-provider-config.yaml

# Wait for the Azure provider Config to be ready
kubectl wait --for=condition=ready providerconfig.azure.upbound.io/crossplane-provider-azure-config --timeout=120s

# Create a service principal for Crossplane to use with Azure
az account set --subscription "$subscriptionId"
$account = az account show | ConvertFrom-Json
$subId = $account.id

if (-not $subId) {
    Write-Host "Unable to retrieve Azure subscription ID. Please check your Azure CLI configuration."
    exit
} else {
    Write-Host "Using Azure subscription ID: $subId"
}

$sp = az ad sp create-for-rbac --name "${name}-deployment-sp" | ConvertFrom-Json

$role = az role assignment create --assignee $sp.appId --role "Owner" --scope "/subscriptions/${subId}"  | ConvertFrom-Json

# Check if Role Assignment was successful
if ($null -eq $role) {
    Write-Host "Role assignment failed. Please check the Azure CLI output for details."
    exit
} else {
    Write-Host "Role assignment successful. Service Principal has been granted Owner role."
}

# Prepare the credentials for Crossplane
$credentials = @{
    clientId    = $sp.appId
    clientSecret = $sp.password
    tenantId    = $sp.tenant
}

# Convert the credentials to a JSON string
$jsonCredentials = $credentials | ConvertTo-Json -Depth 3

# Encode the JSON string to Base64
$encodedCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jsonCredentials))

# Create a Kubernetes secret with the encoded credentials
kubectl create secret generic azure-secret -n crossplane-system --from-literal=creds=$encodedCredentials
