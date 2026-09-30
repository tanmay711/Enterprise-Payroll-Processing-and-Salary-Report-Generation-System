# Enterprise Payroll Processing and Salary Report Generation System

An enterprise batch payroll engine that emulates **IBM z/OS mainframe architecture** (DFSORT, DB2/VSAM lookups, JCL control, and COBOL business logic) entirely on a local PC using **GnuCOBOL** and shell automation — with a **Flask web dashboard** for interaction.

![z/OS Emulation](https://img.shields.io/badge/z%2FOS-Emulation-blue)
![GnuCOBOL](https://img.shields.io/badge/GnuCOBOL-3.1.2-green)
![Flask](https://img.shields.io/badge/Flask-Web_Dashboard-orange)
![Python](https://img.shields.io/badge/Python-3.10-yellow)

---

## System Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │         JCL EMULATION (run_batch.sh)        │
                    │                                             │
  raw_timecards.dat │  STEP01 ─► STEP02 ─► STEP03 ─► STEP04 ─► STEP05  │
  ─────────────────►│  Verify    DFSORT    Compile   Execute   Verify   │
                    │  Compiler  Sort      COBOL     Payroll   Output   │
                    │                                             │
                    └──────────────────┬──────────────────────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              ▼                        ▼                        ▼
   MONTHLY_PAYSLIP         DEPT_PAYROLL              PAYROLL_EXCEPTION
   _REPORT.txt             _SUMMARY.txt             _LOG.txt
```

## Features

- **903-line COBOL program** (`PAYPROC01.cbl`) with structured paragraphs
- **DFSORT emulation** — sorts timecards by Employee ID
- **DB2 simulation** — employee master table loaded into in-memory arrays
- **VSAM KSDS simulation** — keyed tax rate index lookup
- **JCL batch control** — 5-step pipeline with return code checking
- **4-gate validation** — numeric ID, valid hours, employee exists, tax bracket exists
- **Payroll calculations** — regular pay, overtime (1.5x), federal/state taxes, insurance deductions
- **3 output reports** — payslips, department summary, exception log
- **Flask web dashboard** — view data, edit timecards, run batch, view reports in browser

## Project Structure

```
payroll-system/
├── app.py                               # Flask web dashboard server
├── templates/
│   └── dashboard.html                   # Single-page web UI
├── src/
│   └── PAYPROC01.cbl                    # 903-line COBOL payroll engine
├── scripts/
│   ├── run_batch.sh                     # JCL emulation (5-step bash script)
│   └── run_batch.bat                    # Windows wrapper
├── data/
│   ├── input/
│   │   └── raw_timecards.dat            # Employee timecards (13 records)
│   ├── ref/
│   │   ├── employee_master.dat          # 10 employees across 4 departments
│   │   └── tax_rates_index.dat          # 5 tax brackets (A-E)
│   ├── work/
│   │   └── sorted_timecards.dat         # DFSORT output
│   └── output/
│       ├── MONTHLY_PAYSLIP_REPORT.txt   # Employee payslip listing
│       ├── DEPT_PAYROLL_SUMMARY.txt     # Department audit summary
│       └── PAYROLL_EXCEPTION_LOG.txt    # Error records with return codes
└── .gitignore
```

## Prerequisites

| Requirement | Purpose |
|------------|---------|
| **WSL (Ubuntu)** | Linux environment for GnuCOBOL |
| **GnuCOBOL** | COBOL compiler (`cobc`) |
| **Python 3.10+** | Web dashboard server |
| **Flask** | Web framework (`pip install flask`) |

### Install GnuCOBOL (one-time setup)

```powershell
wsl -d Ubuntu -u root -- bash -c "apt-get update && apt-get install -y gnucobol"
```

### Install Flask (one-time setup)

```powershell
pip install flask
```

## How to Run

### Option 1: Command Line (COBOL batch only)

```powershell
wsl -d Ubuntu -- bash -c "cd '/mnt/d/College Assigments/TY/Mainframe/Cp/payroll-system' && bash scripts/run_batch.sh"
```

### Option 2: Web Dashboard (recommended)

```powershell
cd "D:\College Assigments\TY\Mainframe\Cp\payroll-system"
python app.py
```

Then open **http://localhost:5000** in your browser.

| Tab | What it does |
|-----|-------------|
| **Dashboard** | Shows employee master, tax brackets, report status |
| **Input Data** | View/edit timecard records with live validation |
| **Run Batch** | Execute the full COBOL pipeline with one click |
| **Payslip Report** | View generated payslip report |
| **Dept Summary** | View department audit totals |
| **Exception Log** | View rejected records with error codes |

## Data Formats

### Timecard Record (9 bytes)
```
Position:  1----5  6--8  9
Field:     EMP-ID  HRS   TAX
Example:   10002   455   B     → Employee 10002, 45.5 hours, Bracket B
```

### Employee Master (39 bytes)
```
Position:  1----5  6-----------25  26-29  30---34  35---39
Field:     EMP-ID  FULL NAME       DEPT   RATE     INSURANCE
Example:   10002   PATEL, ANITA    FIN    03500    01500
```

### Tax Rates Index (7 bytes)
```
Position:  1     2--4   5--7
Field:     CODE  STATE  FEDERAL
Example:   B     015    025     → Bracket B: 15% state, 25% federal
```

## Payroll Calculation

```
Regular Pay   = Min(Hours, 40.0) × Hourly Rate
Overtime Pay  = Max(0, Hours - 40.0) × (Hourly Rate × 1.5)
Gross Salary  = Regular Pay + Overtime Pay
Deductions    = (Gross × Federal Tax) + (Gross × State Tax) + Insurance
Net Pay       = Gross Salary - Deductions
```

## Validation Rules

| Error Code | Condition | Example |
|-----------|-----------|---------|
| **ERR-01** | Non-numeric Employee ID or zero/invalid hours | `ABCDE400A`, `10003000C` |
| **ERR-02** | Employee ID not found in master table | `99999400B` |
| **ERR-03** | Tax bracket code not A through E | Any invalid bracket |

## Mainframe ↔ PC Mapping

| IBM z/OS Concept | PC Equivalent |
|-----------------|---------------|
| JCL Job Steps | `run_batch.sh` (bash) |
| DFSORT | `sort -k1,1` |
| IKFCBL00 Compiler | `cobc -x` (GnuCOBOL) |
| DB2 Table | `employee_master.dat` → COBOL arrays |
| VSAM KSDS | `tax_rates_index.dat` → COBOL arrays |
| DD Statements | Environment variables |
| SYSOUT Class A | Console output / text files |
| Return Codes | Process exit codes |

## Sample Output

```
 EMP-ID EMPLOYEE NAME         DEPT  HOURS  REGULAR PAY OVERTIME    GROSS PAY   DEDUCTIONS  NET PAY
 ------ --------------------  ----  -----  ----------- ----------- ----------- ----------- -----------
 10001  SHARMA, RAJESH        HR     40.0    1,000.00       0.00   1,000.00     312.00     688.00
 10002  PATEL, ANITA          FIN    45.5    1,400.00     288.75   1,688.75     690.49     998.26
 10003  KUMAR, VIKRAM         ENG    38.0    1,596.00       0.00   1,596.00     816.00     780.00
 ...
 GRAND TOTALS:                          14,586.25                  7,278.88     7,307.37
```

## License

MIT
