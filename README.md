# 🔐 BitLocker AD Deployment

> Automated BitLocker deployment with TPM and Active Directory key backup using PowerShell.

---

## 📋 Table of Contents

- [📖 Overview](#-overview)
- [✨ Features](#-features)
- [⚙️ Requirements](#️-requirements)
- [🚀 Usage](#-usage)
- [🧠 How It Works](#-how-it-works)
- [🛡️ Security Notes](#️-security-notes)
- [⚠️ Troubleshooting](#️-troubleshooting)
- [📁 Project Structure](#-project-structure)
- [📌 TODO / Improvements](#-todo--improvements)
- [📜 License](#-license)

---

## 📖 Overview

This PowerShell script automates the deployment of **BitLocker encryption** on Windows systems using:

- 🔐 **TPM (Trusted Platform Module)**
- 🧩 **AES encryption (128 or 256 bits)**
- 🗂️ **Active Directory backup of recovery keys**

It is designed for **enterprise environments** to simplify and standardize BitLocker deployment across multiple machines.

---

## ✨ Features

- ✅ Automatic TPM detection and validation  
- 🔐 BitLocker activation with TPM protector  
- ⚡ Supports **AES128 / AES256 encryption**  
- 💾 Optional **Used Space Only** encryption  
- 🗃️ Automatic **recovery key backup to Active Directory**  
- 🔁 Fallback to `manage-bde` if native backup fails  
- 📊 Real-time encryption progress monitoring  
- 🧱 Safe checks (admin rights, TPM readiness, etc.)

---

## ⚙️ Requirements

- 🖥️ Windows 10 / 11 **Pro or Enterprise**
- 🔐 TPM enabled and ready (via BIOS/UEFI)
- 🧑‍💻 Local Administrator privileges
- 🏢 Active Directory environment (for key backup)
- 📜 PowerShell with BitLocker module available

---

## 🚀 Usage

### ▶️ Basic execution

```powershell
.\Enable-BitLocker_Deploy.ps1
```

### ⚙️ With parameters

```powershell
.\Enable-BitLocker_Deploy.ps1 -MountPoint "C:" -EncryptionMethod Aes256 -UsedSpaceOnly
```

### 🧾 Parameters

| Parameter          | Description                                | Default  |
| ------------------ | ------------------------------------------ | -------- |
| `MountPoint`       | Target drive to encrypt                    | `C:`     |
| `EncryptionMethod` | Encryption algorithm (`Aes128` / `Aes256`) | `Aes256` |
| `UsedSpaceOnly`    | Encrypt only used disk space               | Off      |

---

## 🧠 How It Works

1. 🔎 Checks if the script is run as Administrator
2. 🔐 Verifies TPM presence and readiness
3. 📦 Retrieves BitLocker volume information
4. 🔑 Adds TPM protector if missing
5. 🚀 Starts BitLocker encryption
6. 💾 Backs up recovery key to Active Directory
7. 📊 Monitors encryption progress until completion

---

## 🛡️ Security Notes

* 🔒 Always test in a **lab environment** before production deployment
* 🧪 Ensure TPM and Secure Boot are properly configured in BIOS/UEFI
* 📂 Verify that **Group Policy allows AD key backup**
* 🔑 Confirm recovery keys are stored in Active Directory

---

## ⚠️ Troubleshooting

### ❌ TPM not ready

* Check BIOS/UEFI settings (TPM / Secure Boot)

### ❌ Backup to AD fails

* Verify:

  * Domain join
  * GPO configuration
  * Permissions

### ❌ BitLocker does not start

* Ensure:

  * Correct Windows edition
  * No conflicting policies
  * Disk is eligible

---

## 📁 Project Structure

```
.
├── .gitattributes
├── Enable-BitLocker_Deploy.ps1
└── README.md
```

---

## 📌 TODO / Improvements

* 🔄 Add logging to file (log system)
* 🌐 Remote deployment support (WinRM / Intune / SCCM)
* 📊 Centralized reporting dashboard
* 🧩 Integration with monitoring tools (Zabbix, etc.)
* 🔐 Support for additional protectors (PIN, USB key)

---

## 📜 License

This project is provided for **educational and enterprise usage**.

---

## 👨‍💻 Author

**Lukas Mauffré**
💼 IT Department (DSI) – UFCV 
