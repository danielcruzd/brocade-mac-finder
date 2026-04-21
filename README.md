# 🔍 Brocade MAC Address Finder (PowerShell)

A PowerShell script to search for a MAC address across multiple network switches via Telnet.  
Designed for environments using Brocade / Ruckus ICX switches.

---

## 📌 Features

- Search a MAC address across multiple switches
- Supports **parallel execution** (PowerShell 7+)
- Handles **timeouts and connection errors**
- Cleans Telnet output automatically
- Flexible MAC input (8–12 hex digits, any format)
- Displays clean and structured results

---

## 🧰 Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Network access to switches (Telnet enabled)
- Valid access to switch CLI (no authentication handled in this version)

---

## ⚙️ Parameters

| Parameter     | Description |
|--------------|------------|
| `-Hosts`     | List of switch IP addresses |
| `-Port`      | Telnet port (default: 23) |
| `-TimeoutMs` | Read timeout per host (default: 3000 ms) |
| `-Parallel`  | Enables parallel execution (PowerShell 7+) |

---

## 🚀 Usage

### Basic execution
```powershell
.\Search-MacAddress.ps1
