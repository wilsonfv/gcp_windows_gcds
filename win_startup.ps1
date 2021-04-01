$Path = $env:TEMP;

Write-Host "download GCDS";
$GcdsInstaller = "dirsync-win64.exe";
Invoke-WebRequest "https://dl.google.com/dirsync/dirsync-win64.exe" -OutFile $Path\$GcdsInstaller;
Start-Process -FilePath $Path\$GcdsInstaller -Args "/silent /install" -Verb RunAs -Wait;
Remove-Item $Path\$GcdsInstaller;

Write-Host "download chrome";
$ChromeInstaller = "ChromeSetup.exe";
Invoke-WebRequest "https://dl.google.com/tag/s/appguid%3D%7B8A69D345-D564-463C-AFF1-A69D9E530F96%7D%26iid%3D%7B277F20EA-8380-6D11-1544-0DC96EC87AB4%7D%26lang%3Den%26browser%3D2%26usagestats%3D1%26appname%3DGoogle%2520Chrome%26needsadmin%3Dprefers%26ap%3Dx64-stable-statsdef_1%26brand%3DONGR%26installdataindex%3Dempty/update2/installers/ChromeSetup.exe" -OutFile $Path\$ChromeInstaller;
Start-Process -FilePath $Path\$ChromeInstaller -Args "/silent /install" -Verb RunAs -Wait;
Remove-Item $Path\$ChromeInstaller;
