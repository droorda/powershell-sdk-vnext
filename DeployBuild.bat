pushd %~dp0

rename kemp-powershell-vnext Kemp.LoadBalancer.Powershell
powershell.exe -inputformat none -ExecutionPolicy Bypass -noprofile -NonInteractive -command "& .\Build\Start-Build.ps1 -Task Deploy"
rename Kemp.LoadBalancer.Powershell kemp-powershell-vnext

popd

pause
