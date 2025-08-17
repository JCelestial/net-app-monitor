# App Monitor for .NET IIS Startup Errors

A PowerShell-based monitoring tool to detect **.NET IIS startup errors** (initially `500.37`), notify administrators, and optionally restart the application.  
This repo includes scripts, sample configs, test data, and Docker-based environments for safe development & testing.

---

## Quickstart for Developers

### Build Dummy .NET Web App to Test Scripts Locally 
To test the application runs locally
```bash
cd web-app-dummy
dotnet restore
dotnet build
dotnet run
```
Open the app on `http://localhost:5000` to verify the application has booted successfully

Also try the following endpoints
```bash
http://localhost:5000/simulate50037
http://localhost:5000/slow
```
`/simulate50037` should display the message `Simulated 500.37 logged.`

`/slow` should display the message `Done after 5s.`

## Prerequisites

### Turn On IIS
- Control Panel => "Turn Windows features on or off" => check:
  - Internet Information Service => Web Management Tools => IIS Management Console
  - Internet Information Service => World Wide Web Services (default sub-features are fine)

- Install the [ASP.NET Core Hosting Bundle](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/iis/hosting-bundle?view=aspnetcore-9.0) that matches your target (ideally .NET 8.0)
  - Tip: verify with `& "$env:ProgramFiles\dotnet\dotnet.exe" --info`
  

To publish the App as an IIS Web App, run the following script:
```bash
# basic
.\scripts\bootstrap-IIS.ps1 -ProjectPath "<your-repo-path>\web-app-dummy\TestApp.csproj"

# with stdout logs + startup time limit + custom port
.\scripts\bootstrap-IIS.ps1 `
  -ProjectPath "<your-repo-path>\web-app-dummy\TestApp.csproj" `
  -EnableStdoutLogs `
  -StartupTimeLimitSeconds 5 `
  -Port 8080 `
  -EventLogSource "TestApp"
```



To teardown setup for a clean workspace
```bash
# basic
.\Teardown-IIS-TestApp.ps1

# or with your own names/paths:
.\Teardown-IIS-TestApp.ps1 `
  -SiteName "MyLocalSite" `
  -AppPoolName "MyPool" `
  -PhysicalPath "C:\inetpub\wwwroot\MyApp"
```


