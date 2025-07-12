$githubUsername= "your-github-username"
$githubToken= "your-github-token"
$repositoryName = "platform-gitops-demo"

$env:GITHUB_USERNAME = $githubUsername
$env:GITHUB_TOKEN = $githubToken


# Install Flux CLI

switch ($PSVersionTable.Platform) {
    'Win32NT' { 
        Write-Host "Installing Flux - Windows OS (non-interactive)" 
        choco install -y flux
    }
    'Unix' {
        if ((uname) -eq 'Darwin') {
            Write-Host "Installing Flux - macOS (non-interactive)"
            brew install --quiet --no-interactive fluxcd/tap/flux
        } else {
            Write-Host "Installing Flux - Unix/Linux (non-interactive)"
            Invoke-Expression "& { $(Invoke-RestMethod https://fluxcd.io/install.sh) }"
        }
    }
        Default { Write-Host "Unknown OS" }
    }

flux bootstrap github `
  --token-auth `
  --owner=$githubUsername `
  --repository=$repositoryName `
  --branch=main `
  --path=clusters/my-cluster `
  --personal