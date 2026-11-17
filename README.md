# Enterprise Payroll Processing and Salary Report Generation System

An enterprise batch payroll engine that emulates **IBM z/OS mainframe architecture** (DFSORT, DB2/VSAM lookups, JCL control, COBOL business logic, and **RACF/SAF Security**) entirely on a local PC using **GnuCOBOL** and shell automation — with a **Flask web dashboard** and **Chart.js visual analytics**.

![z/OS Emulation](https://img.shields.io/badge/z%2FOS-Emulation-blue)
![GnuCOBOL](https://img.shields.io/badge/GnuCOBOL-3.1.2-green)
![RACF & SAF](https://img.shields.io/badge/RACF%20%26%20SAF-Security_Layer-red)
![SMF Type 80](https://img.shields.io/badge/SMF-Type_80_Audit-purple)
![Flask](https://img.shields.io/badge/Flask-Web_Dashboard-orange)
![Chart.js](https://img.shields.io/badge/Chart.js-Analytics_Suite-brightgreen)

---

## System Architecture

```
                    ┌─────────────────────────────────────────────────────────┐
                    │               JCL EMULATION (run_batch.sh)              │
                    │                                                         │
  raw_timecards.dat │  STEP00 ─► STEP01 ─► STEP02 ─► STEP03 ─► STEP04 ─► STEP05  │
  ─────────────────►│  RACFCHK   Verify    DFSORT    Compile   Execute   Verify   │
                    │  Security  Compiler  Sort      COBOL     Payroll   Output   │
                    │                                                         │
                    └────────────────────────────┬────────────────────────────┘
                                                 │
            ┌────────────────────────────┬───────┴────────────┬────────────────────────────┐
            ▼                            ▼                    ▼                            ▼
   MONTHLY_PAYSLIP              DEPT_PAYROLL         PAYROLL_EXCEPTION           SMF80_SECURITY
   _REPORT.txt                  _SUMMARY.txt         _LOG.txt                    _AUDIT.log
```

---

## 🔒 Mainframe Security Architecture (RACF & SAF)

To match actual enterprise IBM z/OS mainframe security standards, the system includes a dedicated **RACF (Resource Access Control Facility)** and **SAF (System Authorization Facility)** security layer:

### 1. Role-Based Access Control (RBAC) & Mainframe Identities

| RACF User ID | Group | Mainframe Role | Authority Level | Permitted Actions |
|-------------|-------|----------------|-----------------|-------------------|
| **`IBMUSER`** | `SYSADMIN` | Chief Security Officer / SysProg | `ALTER` (Full Control) | Submit JCL, update datasets, manage security profiles, rehash integrity manifests |
| **`OPER01`** | `OPERGRP` | Console Operator | `EXECUTE` | Submit JCL batch jobs, view JES2 spools and reports (cannot edit datasets or salary rates) |
| **`PAYCLRK1`** | `PAYROLL` | Payroll Operations Officer | `UPDATE` | Edit and save raw timecards, view employee master (cannot submit batch jobs without operator authority) |
| **`AUDIT01`** | `AUDITGRP` | Internal Compliance Auditor | `READ` | Read-only access to reports, department summaries, and SMF Type 80 logs (zero write or execute authority) |

### 2. Resource Profiles & Access Control Lists (ACL)

Protected resources are categorized into mainframe SAF resource classes:
- **`FACILITY: JOB.PAYPROC01.SUBMIT`**: Enforces that only `SYSADMIN` and `OPERGRP` can submit batch executions. Attempts by unauthorized users (`AUDIT01` or `PAYCLRK1`) immediately trigger **SAF Return Code RC=0008, RACF RC=0008 (Security ABEND)**.
- **`DATASET: DATA.INPUT.TIMECARDS`**: Requires `UPDATE` authority to modify ingestion data.
- **`DATASET: DATA.REF.EMPLOYEE.MASTER`**: Read-protected DB2 employee master dataset.
- **`DATASET: DATA.REF.TAX.RATES`**: Read-protected VSAM KSDS tax rate dataset.
- **`FACILITY: SECURITY.RACF.CONFIG`**: Requires `ALTER` authority to modify security rules or cryptographic baselines.

### 3. Cryptographic Dataset Integrity (Pervasive Encryption)
- Master reference tables (`employee_master.dat` and `tax_rates_index.dat`) have baseline **SHA-256 cryptographic digests** stored in a secured manifest.
- In **STEP00 (`PGM=RACFCHK`)**, the batch engine verifies file signatures before processing.
- If an unauthorized party alters salary rates or tax brackets out-of-band, the security gate detects a signature mismatch and immediately halts the job with **Security ABEND `RC=0016`**.

### 4. SMF Type 80 Security Audit Trail
Every security-relevant event (logons, authorization checks, batch job submissions, dataset modifications, and access violations) is logged in real-time to `data/output/SMF80_SECURITY_AUDIT.log` using standard IBM SMF-80 format:
```
[SMF-80] 2026-11-17 23:14:09 | IBMUSER  | SYSADMIN | AUTH_CHECK | JOB.PAYPROC01.SUBMIT     | EXECUTE | PERMITTED | RC=0000 | RC=0000 | ACCESS GRANTED VIA SYSADMIN PROFILE
[SMF-80] 2026-11-17 23:14:09 | AUDIT01  | AUDITGRP | AUTH_CHECK | JOB.PAYPROC01.SUBMIT     | EXECUTE | VIOLATION | RC=0008 | RC=0008 | INSUFFICIENT ACCESS AUTHORITY
```

---

## Core Engine Features

- **903-line COBOL program** (`PAYPROC01.cbl`) with structured paragraphs
- **JCL Batch Execution** — 6-step pipeline (`STEP00` through `STEP05`)
- **DFSORT Emulation** — sorts timecards by Employee ID
- **DB2 Simulation** — employee master table loaded into in-memory arrays
- **VSAM KSDS Simulation** — keyed tax rate index lookup
- **4-Gate Validation** — numeric ID, valid hours, employee exists, tax bracket exists
- **Payroll Calculations** — regular pay, overtime (1.5x), federal/state taxes, insurance deductions
- **3 Batch Reports** — SYSOUT Class A payslip listing, department summary, and exception log
- **Web Dashboard & Visual Analytics** — 6 interactive Chart.js charts, KPI cards, dark terminal theme, and RACF identity switcher

---

## Project Structure

```
payroll-system/
├── app.py                               # Flask server with RACF & SAF security endpoints
├── security.py                          # IBM RACF, SAF, SMF-80 & SHA-256 integrity module
├── templates/
│   └── dashboard.html                   # Web UI with RACF controls & Chart.js analytics
├── static/
│   └── js/
│       └── chart.min.js                 # Offline bundled Chart.js UMD library
├── src/
│   └── PAYPROC01.cbl                    # 903-line COBOL payroll engine
├── scripts/
│   ├── run_batch.sh                     # JCL emulation (6-step bash script with STEP00 RACF check)
│   └── run_batch.bat                    # Windows wrapper
├── data/
│   ├── input/
│   │   └── raw_timecards.dat            # Employee timecards (13 records)
│   ├── ref/
│   │   ├── employee_master.dat          # 10 employees across 4 departments
│   │   ├── tax_rates_index.dat          # 5 tax brackets (A-E)
│   │   └── .dataset_integrity.json      # Cryptographic SHA-256 reference manifest
│   ├── work/
│   │   └── sorted_timecards.dat         # DFSORT output
│   └── output/
│       ├── MONTHLY_PAYSLIP_REPORT.txt   # Employee payslip listing
│       ├── DEPT_PAYROLL_SUMMARY.txt     # Department audit summary
│       ├── PAYROLL_EXCEPTION_LOG.txt    # Error records with return codes
│       └── SMF80_SECURITY_AUDIT.log     # IBM SMF Type 80 security audit trail
└── README.md
```

---

## How to Run & Demonstrate

### 1. Start the Web Dashboard

```powershell
cd "D:\College Assigments\TY\Mainframe\Cp\payroll-system"
python app.py
```
Open **`http://localhost:5000`** in your browser.

### 2. How to Demonstrate Security to Faculty

1. **Show the Active Identity**:
   - The top header displays: `RACF: IBMUSER (SYSADMIN)`.
   - Click the identity badge or go to the **`🔒 RACF & Security`** tab.
2. **Show the Security Components**:
   - **Access Control Matrix**: Show the resource permissions for each group.
   - **Cryptographic Dataset Integrity**: Show the live SHA-256 hashes of `employee_master.dat` and `tax_rates_index.dat` showing "VERIFIED SECURE".
   - **Live SMF Type 80 Security Log**: Show logged security events.
3. **Trigger a Security Violation (Access Denied Demo)**:
   - Click **"Switch RACF Identity"** and select **`AUDIT01`** (Internal Compliance Auditor).
   - Go to the **`Run Batch`** tab. Notice the red warning: *Active identity lacks EXECUTE authority*.
   - Click **`▶ SUBMIT JOB PAYPROC01`**.
   - The console immediately ABENDs:
     `** SECURITY ABEND: SAF RC=0008 RACF RC=0008`
     `INSUFFICIENT ACCESS AUTHORITY (REQUIRED=EXECUTE, GRANTED=NONE)`
   - Go to **`RACF & Security`** tab: Show the new `VIOLATION` record logged in SMF Type 80!
4. **Demonstrate Authorized Execution**:
   - Switch identity back to **`IBMUSER`** or **`OPER01`**.
   - Submit the job again — it successfully runs all steps (`STEP00` through `STEP05`) with `RC=0000`!

---

## Mainframe ↔ PC Mapping

| IBM z/OS Mainframe Concept | PC Implementation Equivalent |
|----------------------------|------------------------------|
| **RACF / SAF Interface** | `security.py` (User & Group ACL profiles, `check_authority`) |
| **SMF Type 80 Records** | `SMF80_SECURITY_AUDIT.log` (Standard IBM audit trail) |
| **Pervasive Encryption / CPACF** | SHA-256 cryptographic dataset integrity checking |
| **JCL Job Steps** | `run_batch.sh` (6-step bash script) |
| **DFSORT** | `sort -k1,1` |
| **IKFCBL00 Compiler** | `cobc -x` (GnuCOBOL) |
| **DB2 Master Table** | `employee_master.dat` → in-memory COBOL array |
| **VSAM KSDS Keyed File** | `tax_rates_index.dat` → keyed in-memory lookup |
| **DD Statements** | Environment variables (`TIMECARD_FILE`, `EMPMASTER_FILE`) |
| **SYSOUT Class A** | Formatted report listings |
| **Return Codes** | JCL/Process exit codes (`RC=0000`, `RC=0016`) |

---

## License

MIT
