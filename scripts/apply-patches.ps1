. "$env:GITHUB_WORKSPACE/scripts/ps_support.ps1"

cd runtime
git reset --hard $env:DOTNETRUNTIME_COMMIT

Invoke-Expression "git rev-parse --short HEAD" | Out-String -NoNewLine -OutVariable BASE_DOTNET_SHORT_COMMIT

echo dotnet/runtime base SHA1: $BASE_DOTNET_SHORT_COMMIT
echo "BASE_DOTNET_SHORT_COMMIT=$BASE_DOTNET_SHORT_COMMIT" >> $env:GITHUB_ENV

$files = @(Get-ChildItem ../patches/*.patch)
foreach ($file in $files) 
{
    echo "Applying patch $file"
    git apply --whitespace=fix $file
    ThrowOnNativeFailure
}

git config --global user.email "ci@platform.uno"
git config --global user.name "Uno Platform CI"
git add .
git commit -m "apply patches"

Invoke-Expression "git rev-parse --short HEAD" | Out-String -NoNewLine -OutVariable PATCHED_DOTNET_SHORT_COMMIT
echo dotnet/runtime patched SHA1: $PATCHED_DOTNET_SHORT_COMMIT