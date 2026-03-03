# Windows Scripts

## 🎯 Overview

This folder contains **standalone PowerShell scripts** used to perform targeted administrative tasks in Microsoft Intune for Windows device management. Each script is designed to address a specific scenario and does not rely on a full project structure.

---

## 📜 Scripts

| Script | Description |
|--------|-------------|
| [Convert-CertificatetoCSP.ps1](Convert-CertificatetoCSP.ps1) | A GUI-based utility that streamlines the creation of custom Intune policies in CSP format for certificate deployment. It extracts the details from a local certificate files (.cer, .crt, .der) and generates the required OMA-URI path and Base64 encoding, enabling you to either build policies manually using this information or deploying them directly to Intune using the Microsoft Graph API.|
| [Start-AutopilotRegistrationGUID.ps1](Start-AutopilotRegistrationGUID.ps1) | A WPF GUI tool for managing Windows Autopilot device registrations. Connects to Microsoft Graph API to retrieve Autopilot profiles, extract OrderID group tags, and register devices with the appropriate profile assignments.|

---

## 🚀 Running Scripts Directly from Repository

You can execute any script directly from this repository without downloading it first. Use the following PowerShell command format:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/RicardoGFGomes/Intune/refs/heads/main/Windows/[ScriptName].ps1' -UseBasicParsing).Content"
```

### Example:

**Start-AutopilotRegistrationGUID.ps1:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/RicardoGFGomes/Intune/refs/heads/main/Windows/Start-AutopilotRegistrationGUID.ps1' -UseBasicParsing).Content"
```

---

## ⚠️ Disclaimer

This script is provided **as-is** without any warranty or support. The author assumes no responsibility for any issues, damages, or unintended consequences arising from the use of this tool. Use it at your own risk.

This project is offered to the public for educational and testing purposes. No official support, maintenance, or updates are guaranteed. By using this script, you acknowledge and accept these terms.
