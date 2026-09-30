#!/bin/bash
#=====================================================================
# JCL EMULATION SCRIPT - ENTERPRISE PAYROLL BATCH PROCESSING
# Emulates IBM z/OS JCL Job Steps on Linux/WSL via GnuCOBOL
#=====================================================================
# JOB PAYPROC  CLASS=A,MSGCLASS=X,MSGLEVEL=(1,1)
#=====================================================================

set -e

echo "========================================================="
echo " JOB: PAYPROC01 - ENTERPRISE PAYROLL BATCH ENGINE"
echo " JOBCLASS: A   MSGCLASS: X   MSGLEVEL: (1,1)"
echo " SUBMITTED: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================="
echo ""

# --- Resolve base directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Dataset Directory Assignments (DD Emulation) ---
INPUT_DIR="$BASE_DIR/data/input"
REF_DIR="$BASE_DIR/data/ref"
WORK_DIR="$BASE_DIR/data/work"
OUTPUT_DIR="$BASE_DIR/data/output"
SRC_DIR="$BASE_DIR/src"

RC=0

#=====================================================================
# STEP01: VERIFY COMPILER (IEFBR14 EQUIVALENT)
#=====================================================================
echo "//STEP01  EXEC PGM=IEFBR14,PARM='VERIFY COMPILER'"
echo "-----------------------------------------------------------"

if ! command -v cobc &> /dev/null; then
    echo "** ABEND: GnuCOBOL compiler (cobc) not found!"
    echo "   Install with: sudo apt-get install gnucobol"
    echo "   STEP01 RC=0012"
    exit 12
fi

COBC_VERSION=$(cobc --version | head -1)
echo "  COMPILER: $COBC_VERSION"
echo "  STEP01 RC=0000"
echo ""

#=====================================================================
# STEP02: DFSORT EMULATION - SORT TIMECARDS BY EMP-ID
#=====================================================================
echo "//STEP02  EXEC PGM=DFSORT"
echo "//SORTIN   DD DSN=DATA.INPUT.TIMECARDS,DISP=SHR"
echo "//SORTOUT  DD DSN=DATA.WORK.SORTED,DISP=(NEW,CATLG)"
echo "//SYSIN    DD *"
echo "  SORT FIELDS=(1,5,CH,A)"
echo "/*"
echo "-----------------------------------------------------------"

if [ ! -f "$INPUT_DIR/raw_timecards.dat" ]; then
    echo "** ABEND: Input dataset DATA.INPUT.TIMECARDS not found!"
    echo "  STEP02 RC=0008"
    exit 8
fi

# Convert Windows line endings to Unix if present
sed -i 's/\r$//' "$INPUT_DIR/raw_timecards.dat"

# Sort by columns 1-5 (EMP-ID), ascending - emulating DFSORT
sort -k1,1 "$INPUT_DIR/raw_timecards.dat" > "$WORK_DIR/sorted_timecards.dat"

SORT_COUNT=$(wc -l < "$WORK_DIR/sorted_timecards.dat")
echo "  RECORDS SORTED: $SORT_COUNT"
echo "  OUTPUT: $WORK_DIR/sorted_timecards.dat"
echo "  STEP02 RC=0000"
echo ""

#=====================================================================
# STEP03: COMPILE COBOL SOURCE (IKFCBL00 EMULATION)
#=====================================================================
echo "//STEP03  EXEC PGM=IKFCBL00,PARM='COMPILE'"
echo "//SYSIN    DD DSN=SRC.PAYPROC01.CBL,DISP=SHR"
echo "//SYSLIN   DD DSN=LOAD.PAYPROC01,DISP=(NEW,CATLG)"
echo "-----------------------------------------------------------"

# Convert COBOL source line endings
sed -i 's/\r$//' "$SRC_DIR/PAYPROC01.cbl"

# Also fix line endings on reference files
sed -i 's/\r$//' "$REF_DIR/employee_master.dat"
sed -i 's/\r$//' "$REF_DIR/tax_rates_index.dat"

# Compile with GnuCOBOL - fixed format, warnings enabled
cobc -x -o "$BASE_DIR/PAYPROC01" \
     -W \
     "$SRC_DIR/PAYPROC01.cbl" 2>&1 || true

# Check if binary was actually produced
if [ ! -f "$BASE_DIR/PAYPROC01" ]; then
    echo "** ABEND: COMPILATION FAILED - NO OUTPUT BINARY"
    echo "  STEP03 RC=0012"
    exit 12
fi

echo "  COMPILATION SUCCESSFUL"
echo "  LOAD MODULE: $BASE_DIR/PAYPROC01"
echo "  STEP03 RC=0000"
echo ""

#=====================================================================
# STEP04: EXECUTE PAYROLL ENGINE (PGM=PAYPROC01)
#=====================================================================
echo "//STEP04  EXEC PGM=PAYPROC01"
echo "//TIMECRD  DD DSN=DATA.WORK.SORTED,DISP=SHR"
echo "//EMPMASTR DD DSN=DATA.REF.EMPLOYEE.MASTER,DISP=SHR"
echo "//TAXINDEX DD DSN=DATA.REF.TAX.RATES,DISP=SHR"
echo "//PAYSLIP  DD DSN=DATA.OUTPUT.PAYSLIP,DISP=(NEW,CATLG)"
echo "//DEPTSUMM DD DSN=DATA.OUTPUT.DEPTSUMM,DISP=(NEW,CATLG)"
echo "//EXCLOG   DD DSN=DATA.OUTPUT.EXCLOG,DISP=(NEW,CATLG)"
echo "//SYSOUT   DD SYSOUT=A"
echo "-----------------------------------------------------------"

# Set environment variables for file bindings (DD simulation)
export TIMECARD_FILE="$WORK_DIR/sorted_timecards.dat"
export EMPMASTER_FILE="$REF_DIR/employee_master.dat"
export TAXRATES_FILE="$REF_DIR/tax_rates_index.dat"
export PAYSLIP_FILE="$OUTPUT_DIR/MONTHLY_PAYSLIP_REPORT.txt"
export DEPTSUMM_FILE="$OUTPUT_DIR/DEPT_PAYROLL_SUMMARY.txt"
export EXCLOG_FILE="$OUTPUT_DIR/PAYROLL_EXCEPTION_LOG.txt"

# Execute the compiled COBOL binary
"$BASE_DIR/PAYPROC01"
EXEC_RC=$?

echo ""
if [ $EXEC_RC -ne 0 ]; then
    echo "  ** WARNING: PAYPROC01 returned RC=$EXEC_RC"
    RC=$EXEC_RC
fi
echo "  STEP04 RC=$(printf '%04d' $EXEC_RC)"
echo ""

#=====================================================================
# STEP05: VERIFY OUTPUTS (IEBGENER EQUIVALENT)
#=====================================================================
echo "//STEP05  EXEC PGM=IEBGENER,PARM='VERIFY'"
echo "-----------------------------------------------------------"

VERIFY_OK=true

for OUTFILE in "MONTHLY_PAYSLIP_REPORT.txt" "DEPT_PAYROLL_SUMMARY.txt" "PAYROLL_EXCEPTION_LOG.txt"; do
    if [ -f "$OUTPUT_DIR/$OUTFILE" ]; then
        LINES=$(wc -l < "$OUTPUT_DIR/$OUTFILE")
        SIZE=$(stat --format="%s" "$OUTPUT_DIR/$OUTFILE" 2>/dev/null || stat -f"%z" "$OUTPUT_DIR/$OUTFILE" 2>/dev/null)
        echo "  DATASET: $OUTFILE  RECORDS=$LINES  BYTES=$SIZE  STATUS=OK"
    else
        echo "  DATASET: $OUTFILE  STATUS=MISSING"
        VERIFY_OK=false
    fi
done

if [ "$VERIFY_OK" = true ]; then
    echo "  STEP05 RC=0000"
else
    echo "  STEP05 RC=0004"
    RC=4
fi
echo ""

#=====================================================================
# SYSOUT DISPLAY - PRINT GENERATED REPORTS
#=====================================================================
echo "========================================================="
echo " SYSOUT CLASS A - REPORT OUTPUT LISTING"
echo "========================================================="
echo ""

echo "--- MONTHLY PAYSLIP REPORT ---"
echo ""
cat "$OUTPUT_DIR/MONTHLY_PAYSLIP_REPORT.txt"
echo ""
echo ""

echo "--- DEPARTMENTAL PAYROLL SUMMARY ---"
echo ""
cat "$OUTPUT_DIR/DEPT_PAYROLL_SUMMARY.txt"
echo ""
echo ""

echo "--- PAYROLL EXCEPTION LOG ---"
echo ""
cat "$OUTPUT_DIR/PAYROLL_EXCEPTION_LOG.txt"
echo ""
echo ""

#=====================================================================
# JOB COMPLETION
#=====================================================================
echo "========================================================="
echo " JOB PAYPROC01 COMPLETED"
echo " MAXIMUM RETURN CODE: RC=$(printf '%04d' $RC)"
echo " ENDED: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================="

exit $RC
