@echo off
REM =====================================================================
REM JCL EMULATION SCRIPT - ENTERPRISE PAYROLL BATCH PROCESSING
REM Windows Batch File - Delegates to WSL for GnuCOBOL compilation
REM =====================================================================

echo =========================================================
echo  JOB: PAYPROC01 - ENTERPRISE PAYROLL BATCH ENGINE
echo  PLATFORM: Windows (WSL-delegated GnuCOBOL)
echo  SUBMITTED: %DATE% %TIME%
echo =========================================================
echo.

REM Convert Windows path to WSL path
set "WIN_BASE=%~dp0.."
for %%I in ("%WIN_BASE%") do set "WIN_BASE=%%~fI"

REM Execute via WSL
wsl -d Ubuntu -- bash -c "cd '%WIN_BASE%' 2>/dev/null; WSLPATH=$(wslpath '%WIN_BASE%'); cd \"$WSLPATH\" && bash scripts/run_batch.sh"

echo.
echo =========================================================
echo  JOB PAYPROC01 FINISHED - CHECK OUTPUT FILES
echo =========================================================
pause
