       IDENTIFICATION DIVISION.
       PROGRAM-ID. PAYPROC01.
       AUTHOR. ENTERPRISE-PAYROLL-SYSTEM.
       DATE-WRITTEN. 2026-09-29.
      *================================================================
      * ENTERPRISE PAYROLL PROCESSING ENGINE
      * Emulates IBM z/OS Mainframe Batch Payroll Processing
      * DFSORT Pre-sorted Input -> DB2/VSAM Lookups -> Payroll Calc
      *================================================================

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       REPOSITORY.
           FUNCTION ALL INTRINSIC.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *--- SORTED TIMECARD INPUT (FROM DFSORT PHASE) ---
           SELECT TIMECARD-FILE
               ASSIGN TO WS-TIMECARD-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-TC-STATUS.

      *--- EMPLOYEE MASTER REFERENCE (DB2 EMULATION) ---
           SELECT EMPLOYEE-MASTER-FILE
               ASSIGN TO WS-EMPMASTER-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-EM-STATUS.

      *--- TAX RATES INDEX (VSAM KSDS EMULATION) ---
           SELECT TAX-RATES-FILE
               ASSIGN TO WS-TAXRATES-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-TR-STATUS.

      *--- OUTPUT: MONTHLY PAYSLIP REPORT ---
           SELECT PAYSLIP-REPORT-FILE
               ASSIGN TO WS-PAYSLIP-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PR-STATUS.

      *--- OUTPUT: DEPARTMENT SUMMARY REPORT ---
           SELECT DEPT-SUMMARY-FILE
               ASSIGN TO WS-DEPTSUMM-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-DS-STATUS.

      *--- OUTPUT: EXCEPTION LOG ---
           SELECT EXCEPTION-LOG-FILE
               ASSIGN TO WS-EXCLOG-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-EL-STATUS.

       DATA DIVISION.
       FILE SECTION.

      *--- TIMECARD INPUT RECORD ---
       FD  TIMECARD-FILE
           RECORDING MODE IS F.
       01  TC-RECORD.
           05  TC-EMP-ID              PIC X(5).
           05  TC-HOURS-WORKED        PIC X(3).
           05  TC-TAX-BRACKET         PIC X(1).

      *--- EMPLOYEE MASTER RECORD ---
       FD  EMPLOYEE-MASTER-FILE
           RECORDING MODE IS F.
       01  EM-RECORD.
           05  EM-EMP-ID              PIC X(5).
           05  EM-FULL-NAME           PIC X(20).
           05  EM-DEPT-CODE           PIC X(4).
           05  EM-HOURLY-RATE         PIC X(5).
           05  EM-INSURANCE-DED       PIC X(5).

      *--- TAX RATES INDEX RECORD ---
       FD  TAX-RATES-FILE
           RECORDING MODE IS F.
       01  TR-RECORD.
           05  TR-BRACKET-CODE        PIC X(1).
           05  TR-STATE-TAX           PIC X(3).
           05  TR-FEDERAL-TAX         PIC X(3).

      *--- PAYSLIP REPORT OUTPUT ---
       FD  PAYSLIP-REPORT-FILE
           RECORDING MODE IS F.
       01  PR-RECORD                  PIC X(132).

      *--- DEPARTMENT SUMMARY OUTPUT ---
       FD  DEPT-SUMMARY-FILE
           RECORDING MODE IS F.
       01  DS-RECORD                  PIC X(132).

      *--- EXCEPTION LOG OUTPUT ---
       FD  EXCEPTION-LOG-FILE
           RECORDING MODE IS F.
       01  EL-RECORD                  PIC X(132).

       WORKING-STORAGE SECTION.

      *--- FILE PATH VARIABLES ---
       01  WS-TIMECARD-PATH           PIC X(256).
       01  WS-EMPMASTER-PATH          PIC X(256).
       01  WS-TAXRATES-PATH           PIC X(256).
       01  WS-PAYSLIP-PATH            PIC X(256).
       01  WS-DEPTSUMM-PATH           PIC X(256).
       01  WS-EXCLOG-PATH             PIC X(256).

      *--- FILE STATUS CODES ---
       01  WS-TC-STATUS               PIC XX VALUE SPACES.
       01  WS-EM-STATUS               PIC XX VALUE SPACES.
       01  WS-TR-STATUS               PIC XX VALUE SPACES.
       01  WS-PR-STATUS               PIC XX VALUE SPACES.
       01  WS-DS-STATUS               PIC XX VALUE SPACES.
       01  WS-EL-STATUS               PIC XX VALUE SPACES.

      *--- EOF FLAGS ---
       01  WS-TC-EOF                  PIC X VALUE 'N'.
           88  TC-END-OF-FILE         VALUE 'Y'.
       01  WS-EM-EOF                  PIC X VALUE 'N'.
       01  WS-TR-EOF                  PIC X VALUE 'N'.

      *--- WORKING NUMERIC FIELDS ---
       01  WS-HOURS-NUM               PIC 9(2)V9 VALUE ZERO.
       01  WS-HOURLY-RATE-NUM         PIC 9(3)V99 VALUE ZERO.
       01  WS-INSURANCE-NUM           PIC 9(3)V99 VALUE ZERO.
       01  WS-STATE-TAX-RATE          PIC 9V99 VALUE ZERO.
       01  WS-FED-TAX-RATE            PIC 9V99 VALUE ZERO.

      *--- CALCULATION FIELDS ---
       01  WS-REGULAR-HOURS           PIC 9(2)V9 VALUE ZERO.
       01  WS-OVERTIME-HOURS          PIC 9(2)V9 VALUE ZERO.
       01  WS-REGULAR-PAY             PIC 9(7)V99 VALUE ZERO.
       01  WS-OVERTIME-PAY            PIC 9(7)V99 VALUE ZERO.
       01  WS-GROSS-SALARY            PIC 9(7)V99 VALUE ZERO.
       01  WS-FED-TAX-AMT             PIC 9(7)V99 VALUE ZERO.
       01  WS-STATE-TAX-AMT           PIC 9(7)V99 VALUE ZERO.
       01  WS-TOTAL-DEDUCTIONS        PIC 9(7)V99 VALUE ZERO.
       01  WS-NET-PAY                 PIC 9(7)V99 VALUE ZERO.

      *--- EMPLOYEE MASTER TABLE (IN-MEMORY DB2 SIMULATION) ---
       01  WS-EMP-TABLE.
           05  WS-EMP-ENTRY OCCURS 100 TIMES.
               10  WS-ET-EMP-ID       PIC X(5).
               10  WS-ET-NAME         PIC X(20).
               10  WS-ET-DEPT         PIC X(4).
               10  WS-ET-RATE         PIC 9(3)V99.
               10  WS-ET-INSURANCE    PIC 9(3)V99.
       01  WS-EMP-COUNT               PIC 9(3) VALUE ZERO.

      *--- TAX RATES TABLE (IN-MEMORY VSAM SIMULATION) ---
       01  WS-TAX-TABLE.
           05  WS-TAX-ENTRY OCCURS 10 TIMES.
               10  WS-TT-BRACKET      PIC X(1).
               10  WS-TT-STATE-RATE   PIC 9V99.
               10  WS-TT-FED-RATE     PIC 9V99.
       01  WS-TAX-COUNT               PIC 9(2) VALUE ZERO.

      *--- LOOKUP RESULT FLAGS ---
       01  WS-EMP-FOUND               PIC X VALUE 'N'.
       01  WS-TAX-FOUND               PIC X VALUE 'N'.
       01  WS-EMP-IDX                 PIC 9(3) VALUE ZERO.
       01  WS-TAX-IDX                 PIC 9(2) VALUE ZERO.

      *--- DEPARTMENT TOTALS TABLE ---
       01  WS-DEPT-TABLE.
           05  WS-DEPT-ENTRY OCCURS 20 TIMES.
               10  WS-DT-DEPT-CODE    PIC X(4).
               10  WS-DT-HEADCOUNT    PIC 9(5) VALUE ZERO.
               10  WS-DT-TOTAL-GROSS  PIC 9(9)V99 VALUE ZERO.
               10  WS-DT-TOTAL-DED    PIC 9(9)V99 VALUE ZERO.
               10  WS-DT-TOTAL-NET    PIC 9(9)V99 VALUE ZERO.
       01  WS-DEPT-COUNT              PIC 9(2) VALUE ZERO.
       01  WS-DEPT-IDX                PIC 9(2) VALUE ZERO.
       01  WS-DEPT-FOUND              PIC X VALUE 'N'.

      *--- GRAND TOTALS ---
       01  WS-GRAND-GROSS             PIC 9(9)V99 VALUE ZERO.
       01  WS-GRAND-DED               PIC 9(9)V99 VALUE ZERO.
       01  WS-GRAND-NET               PIC 9(9)V99 VALUE ZERO.
       01  WS-TOTAL-RECORDS           PIC 9(5) VALUE ZERO.
       01  WS-VALID-RECORDS           PIC 9(5) VALUE ZERO.
       01  WS-ERROR-RECORDS           PIC 9(5) VALUE ZERO.

      *--- COUNTERS AND INDICES ---
       01  WS-SUB                     PIC 9(3) VALUE ZERO.
       01  WS-I                       PIC 9(3) VALUE ZERO.

      *--- VALIDATION FLAGS ---
       01  WS-VALID-RECORD            PIC X VALUE 'Y'.
       01  WS-ERROR-CODE              PIC X(6) VALUE SPACES.
       01  WS-IS-NUMERIC-FLAG         PIC X VALUE 'Y'.

      *--- DATE/TIME FIELDS ---
       01  WS-CURRENT-DATE.
           05  WS-CURR-YEAR           PIC 9(4).
           05  WS-CURR-MONTH          PIC 9(2).
           05  WS-CURR-DAY            PIC 9(2).
       01  WS-CURRENT-TIME.
           05  WS-CURR-HOUR           PIC 9(2).
           05  WS-CURR-MIN            PIC 9(2).
           05  WS-CURR-SEC            PIC 9(2).
           05  WS-CURR-HUND           PIC 9(2).
       01  WS-TIMESTAMP               PIC X(19) VALUE SPACES.
       01  WS-HDR-DATE                PIC X(10) VALUE SPACES.

      *--- REPORT HEADER LINES ---
       01  WS-PAYSLIP-HDR1.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(60) VALUE ALL '='.
       01  WS-PAYSLIP-HDR2.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(55) VALUE
               'ENTERPRISE PAYROLL SYSTEM - MONTHLY PAYSLIP REPORT'.
       01  WS-PAYSLIP-HDR3.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(14) VALUE 'REPORT DATE: '.
           05  WS-HDR3-DATE  PIC X(10) VALUE SPACES.
       01  WS-PAYSLIP-HDR4.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(60) VALUE ALL '='.

       01  WS-PAYSLIP-COL-HDR.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(7)  VALUE 'EMP-ID '.
           05  FILLER        PIC X(22) VALUE
               'EMPLOYEE NAME         '.
           05  FILLER        PIC X(6)  VALUE 'DEPT  '.
           05  FILLER        PIC X(7)  VALUE 'HOURS  '.
           05  FILLER        PIC X(12) VALUE
               'REGULAR PAY '.
           05  FILLER        PIC X(12) VALUE
               'OVERTIME    '.
           05  FILLER        PIC X(12) VALUE
               'GROSS PAY   '.
           05  FILLER        PIC X(12) VALUE
               'DEDUCTIONS  '.
           05  FILLER        PIC X(12) VALUE
               'NET PAY     '.

       01  WS-PAYSLIP-COL-DASH.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(6)  VALUE ALL '-'.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(20) VALUE ALL '-'.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  FILLER        PIC X(4)  VALUE ALL '-'.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  FILLER        PIC X(5)  VALUE ALL '-'.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  FILLER        PIC X(11) VALUE ALL '-'.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(11) VALUE ALL '-'.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(11) VALUE ALL '-'.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(11) VALUE ALL '-'.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(11) VALUE ALL '-'.

      *--- PAYSLIP DETAIL LINE ---
       01  WS-PAYSLIP-DETAIL.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-PD-EMPID   PIC X(5).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-PD-NAME    PIC X(20).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-PD-DEPT    PIC X(4).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-PD-HOURS   PIC ZZ9.9.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-PD-REGPAY  PIC ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-PD-OTPAY   PIC ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-PD-GROSS   PIC ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-PD-DEDUCT  PIC ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-PD-NET     PIC ZZZ,ZZ9.99.

      *--- GRAND TOTAL LINE ---
       01  WS-GRAND-TOTAL-LINE.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(36) VALUE
               'GRAND TOTALS:                       '.
           05  WS-GT-GROSS   PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(14) VALUE SPACES.
           05  WS-GT-DED     PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-GT-NET     PIC Z,ZZZ,ZZ9.99.

      *--- DEPARTMENT SUMMARY LINES ---
       01  WS-DEPT-HDR1.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(60) VALUE ALL '='.
       01  WS-DEPT-HDR2.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(40) VALUE
               'DEPARTMENTAL PAYROLL AUDIT SUMMARY'.
       01  WS-DEPT-COL-HDR.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  FILLER        PIC X(8)  VALUE 'DEPT    '.
           05  FILLER        PIC X(12) VALUE
               'HEADCOUNT   '.
           05  FILLER        PIC X(16) VALUE
               'TOTAL GROSS     '.
           05  FILLER        PIC X(16) VALUE
               'TOTAL DEDUCT    '.
           05  FILLER        PIC X(16) VALUE
               'TOTAL NET PAY   '.

       01  WS-DEPT-DETAIL.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-DD-DEPT    PIC X(4).
           05  FILLER        PIC X(4)  VALUE SPACES.
           05  WS-DD-HEAD    PIC ZZ,ZZ9.
           05  FILLER        PIC X(4)  VALUE SPACES.
           05  WS-DD-GROSS   PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-DD-DED     PIC Z,ZZZ,ZZ9.99.
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-DD-NET     PIC Z,ZZZ,ZZ9.99.

      *--- EXCEPTION LOG LINES ---
       01  WS-EXC-HDR1.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(60) VALUE ALL '='.
       01  WS-EXC-HDR2.
           05  FILLER        PIC X(5)  VALUE SPACES.
           05  FILLER        PIC X(50) VALUE
               'PAYROLL EXCEPTION LOG - ERROR DATASET'.

       01  WS-EXC-DETAIL.
           05  FILLER        PIC X(1)  VALUE SPACES.
           05  WS-ED-TS      PIC X(19).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-ED-RC      PIC X(6).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-ED-MSG     PIC X(50).
           05  FILLER        PIC X(2)  VALUE SPACES.
           05  WS-ED-REC     PIC X(9).

      *--- TOTALS DISPLAY LINE ---
       01  WS-TOTALS-LINE             PIC X(132) VALUE SPACES.

      *--- RETURN CODE ---
       01  WS-RETURN-CODE             PIC 9(4) VALUE ZERO.

       PROCEDURE DIVISION.
      *================================================================
       0000-MAIN-CONTROL.
      *================================================================
           PERFORM 0100-INITIALIZE
           PERFORM 0150-LOAD-REFERENCE-TABLES
           PERFORM 0180-WRITE-REPORT-HEADERS
           PERFORM 0200-PROCESS-RECORDS
               UNTIL TC-END-OF-FILE
           PERFORM 0800-WRITE-TOTALS
           PERFORM 0900-TERMINATE
           STOP RUN
           .

      *================================================================
       0100-INITIALIZE.
      *================================================================
           ACCEPT WS-CURRENT-DATE FROM DATE YYYYMMDD
           ACCEPT WS-CURRENT-TIME FROM TIME

           INITIALIZE WS-TIMESTAMP
           STRING WS-CURR-YEAR '-' WS-CURR-MONTH '-'
                  WS-CURR-DAY ' ' WS-CURR-HOUR ':'
                  WS-CURR-MIN ':' WS-CURR-SEC
                  DELIMITED BY SIZE
                  INTO WS-TIMESTAMP
           END-STRING

           INITIALIZE WS-HDR-DATE
           STRING WS-CURR-YEAR '-' WS-CURR-MONTH '-'
                  WS-CURR-DAY
                  DELIMITED BY SIZE
                  INTO WS-HDR-DATE
           END-STRING
           MOVE WS-HDR-DATE TO WS-HDR3-DATE

           ACCEPT WS-TIMECARD-PATH
               FROM ENVIRONMENT 'TIMECARD_FILE'
           ACCEPT WS-EMPMASTER-PATH
               FROM ENVIRONMENT 'EMPMASTER_FILE'
           ACCEPT WS-TAXRATES-PATH
               FROM ENVIRONMENT 'TAXRATES_FILE'
           ACCEPT WS-PAYSLIP-PATH
               FROM ENVIRONMENT 'PAYSLIP_FILE'
           ACCEPT WS-DEPTSUMM-PATH
               FROM ENVIRONMENT 'DEPTSUMM_FILE'
           ACCEPT WS-EXCLOG-PATH
               FROM ENVIRONMENT 'EXCLOG_FILE'

           OPEN INPUT  TIMECARD-FILE
           IF WS-TC-STATUS NOT = '00'
               DISPLAY 'ERROR: CANNOT OPEN TIMECARD FILE. '
                   'STATUS=' WS-TC-STATUS
               MOVE 12 TO WS-RETURN-CODE
               STOP RUN
           END-IF

           OPEN OUTPUT PAYSLIP-REPORT-FILE
           OPEN OUTPUT DEPT-SUMMARY-FILE
           OPEN OUTPUT EXCEPTION-LOG-FILE

           INITIALIZE WS-EMP-TABLE
           INITIALIZE WS-TAX-TABLE
           INITIALIZE WS-DEPT-TABLE

           DISPLAY '================================='
               '================'
           DISPLAY ' ENTERPRISE PAYROLL BATCH ENGINE'
               ' - INITIALIZED'
           DISPLAY ' TIMESTAMP: ' WS-TIMESTAMP
           DISPLAY '================================='
               '================'
           .

      *================================================================
       0150-LOAD-REFERENCE-TABLES.
      *================================================================
      *--- LOAD EMPLOYEE MASTER INTO MEMORY (DB2 SIMULATION) ---
           OPEN INPUT EMPLOYEE-MASTER-FILE
           IF WS-EM-STATUS NOT = '00'
               DISPLAY 'ERROR: CANNOT OPEN EMPLOYEE '
                   'MASTER. STATUS=' WS-EM-STATUS
               MOVE 12 TO WS-RETURN-CODE
               STOP RUN
           END-IF

           MOVE ZERO TO WS-EMP-COUNT
           MOVE 'N' TO WS-EM-EOF
           PERFORM UNTIL WS-EM-EOF = 'Y'
               READ EMPLOYEE-MASTER-FILE
                   AT END
                       MOVE 'Y' TO WS-EM-EOF
                   NOT AT END
                       ADD 1 TO WS-EMP-COUNT
                       MOVE EM-EMP-ID TO
                           WS-ET-EMP-ID(WS-EMP-COUNT)
                       MOVE EM-FULL-NAME TO
                           WS-ET-NAME(WS-EMP-COUNT)
                       MOVE EM-DEPT-CODE TO
                           WS-ET-DEPT(WS-EMP-COUNT)
                       COMPUTE WS-ET-RATE(WS-EMP-COUNT)
                           = FUNCTION NUMVAL(
                           EM-HOURLY-RATE) / 100
                       COMPUTE
                           WS-ET-INSURANCE(WS-EMP-COUNT)
                           = FUNCTION NUMVAL(
                           EM-INSURANCE-DED) / 100
               END-READ
           END-PERFORM
           CLOSE EMPLOYEE-MASTER-FILE
           DISPLAY '  EMPLOYEE MASTER LOADED: '
               WS-EMP-COUNT ' RECORDS'

      *--- LOAD TAX RATES INTO MEMORY (VSAM SIMULATION) ---
           OPEN INPUT TAX-RATES-FILE
           IF WS-TR-STATUS NOT = '00'
               DISPLAY 'ERROR: CANNOT OPEN TAX RATES. '
                   'STATUS=' WS-TR-STATUS
               MOVE 12 TO WS-RETURN-CODE
               STOP RUN
           END-IF

           MOVE ZERO TO WS-TAX-COUNT
           MOVE 'N' TO WS-TR-EOF
           PERFORM UNTIL WS-TR-EOF = 'Y'
               READ TAX-RATES-FILE
                   AT END
                       MOVE 'Y' TO WS-TR-EOF
                   NOT AT END
                       ADD 1 TO WS-TAX-COUNT
                       MOVE TR-BRACKET-CODE TO
                           WS-TT-BRACKET(WS-TAX-COUNT)
                       COMPUTE
                           WS-TT-STATE-RATE(WS-TAX-COUNT)
                           = FUNCTION NUMVAL(
                           TR-STATE-TAX) / 100
                       COMPUTE
                           WS-TT-FED-RATE(WS-TAX-COUNT)
                           = FUNCTION NUMVAL(
                           TR-FEDERAL-TAX) / 100
               END-READ
           END-PERFORM
           CLOSE TAX-RATES-FILE
           DISPLAY '  TAX RATES INDEX LOADED: '
               WS-TAX-COUNT ' BRACKETS'
           .

      *================================================================
       0180-WRITE-REPORT-HEADERS.
      *================================================================
           WRITE PR-RECORD FROM WS-PAYSLIP-HDR1
           END-WRITE
           WRITE PR-RECORD FROM WS-PAYSLIP-HDR2
           END-WRITE
           WRITE PR-RECORD FROM WS-PAYSLIP-HDR3
           END-WRITE
           WRITE PR-RECORD FROM WS-PAYSLIP-HDR4
           END-WRITE
           WRITE PR-RECORD FROM WS-PAYSLIP-COL-HDR
           END-WRITE
           WRITE PR-RECORD FROM WS-PAYSLIP-COL-DASH
           END-WRITE

           WRITE EL-RECORD FROM WS-EXC-HDR1
           END-WRITE
           WRITE EL-RECORD FROM WS-EXC-HDR2
           END-WRITE
           WRITE EL-RECORD FROM WS-EXC-HDR1
           END-WRITE
           MOVE SPACES TO EL-RECORD
           STRING ' TIMESTAMP           '
                  'RC      '
                  'DESCRIPTION'
                  '                                       '
                  'RAW RECORD'
                  DELIMITED BY SIZE INTO EL-RECORD
           END-STRING
           WRITE EL-RECORD
           END-WRITE
           MOVE SPACES TO EL-RECORD
           MOVE ALL '-' TO EL-RECORD
           WRITE EL-RECORD
           END-WRITE
           .

      *================================================================
       0200-PROCESS-RECORDS.
      *================================================================
           READ TIMECARD-FILE
               AT END
                   MOVE 'Y' TO WS-TC-EOF
               NOT AT END
                   ADD 1 TO WS-TOTAL-RECORDS
                   MOVE 'Y' TO WS-VALID-RECORD
                   MOVE SPACES TO WS-ERROR-CODE

                   PERFORM 0250-VALIDATE-RECORD

                   IF WS-VALID-RECORD = 'Y'
                       PERFORM 0300-CALCULATE
                       PERFORM 0400-WRITE-PAYSLIP
                       PERFORM 0500-UPDATE-DEPT-TOTALS
                       ADD 1 TO WS-VALID-RECORDS
                   ELSE
                       ADD 1 TO WS-ERROR-RECORDS
                   END-IF
           END-READ
           .

      *================================================================
       0250-VALIDATE-RECORD.
      *================================================================
      *--- RESET TALLY COUNTER ---
           MOVE ZERO TO WS-SUB

      *--- CHECK 1: NUMERIC EMP-ID ---
           MOVE 'Y' TO WS-IS-NUMERIC-FLAG
           IF TC-EMP-ID IS NOT NUMERIC
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'N' TO WS-IS-NUMERIC-FLAG
               MOVE 'ERR-01' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
           END-IF

           IF WS-IS-NUMERIC-FLAG = 'N'
               EXIT PARAGRAPH
           END-IF

      *--- CHECK 2: VALID HOURS (NUMERIC AND > 0) ---
           IF TC-HOURS-WORKED IS NOT NUMERIC
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-01' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

           COMPUTE WS-HOURS-NUM =
               FUNCTION NUMVAL(TC-HOURS-WORKED) / 10
           IF WS-HOURS-NUM <= ZERO
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-01' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- CHECK 3: EMPLOYEE EXISTS IN MASTER ---
           MOVE 'N' TO WS-EMP-FOUND
           MOVE ZERO TO WS-EMP-IDX
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-EMP-COUNT
                  OR WS-EMP-FOUND = 'Y'
               IF TC-EMP-ID = WS-ET-EMP-ID(WS-I)
                   MOVE 'Y' TO WS-EMP-FOUND
                   MOVE WS-I TO WS-EMP-IDX
               END-IF
           END-PERFORM

           IF WS-EMP-FOUND = 'N'
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-02' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
               EXIT PARAGRAPH
           END-IF

      *--- CHECK 4: TAX BRACKET EXISTS ---
           MOVE 'N' TO WS-TAX-FOUND
           MOVE ZERO TO WS-TAX-IDX
           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-TAX-COUNT
                  OR WS-TAX-FOUND = 'Y'
               IF TC-TAX-BRACKET =
                   WS-TT-BRACKET(WS-I)
                   MOVE 'Y' TO WS-TAX-FOUND
                   MOVE WS-I TO WS-TAX-IDX
               END-IF
           END-PERFORM

           IF WS-TAX-FOUND = 'N'
               MOVE 'N' TO WS-VALID-RECORD
               MOVE 'ERR-03' TO WS-ERROR-CODE
               PERFORM 0700-WRITE-EXCEPTION
           END-IF
           .

      *================================================================
       0300-CALCULATE.
      *================================================================
      *--- RETRIEVE REFERENCE DATA ---
           MOVE WS-ET-RATE(WS-EMP-IDX)
               TO WS-HOURLY-RATE-NUM
           MOVE WS-ET-INSURANCE(WS-EMP-IDX)
               TO WS-INSURANCE-NUM
           MOVE WS-TT-STATE-RATE(WS-TAX-IDX)
               TO WS-STATE-TAX-RATE
           MOVE WS-TT-FED-RATE(WS-TAX-IDX)
               TO WS-FED-TAX-RATE

      *--- REGULAR HOURS = MIN(HOURS, 40.0) ---
           IF WS-HOURS-NUM > 40.0
               MOVE 40.0 TO WS-REGULAR-HOURS
           ELSE
               MOVE WS-HOURS-NUM TO WS-REGULAR-HOURS
           END-IF

      *--- OVERTIME HOURS = MAX(0, HOURS - 40.0) ---
           IF WS-HOURS-NUM > 40.0
               COMPUTE WS-OVERTIME-HOURS =
                   WS-HOURS-NUM - 40.0
           ELSE
               MOVE ZERO TO WS-OVERTIME-HOURS
           END-IF

      *--- REGULAR PAY ---
           COMPUTE WS-REGULAR-PAY =
               WS-REGULAR-HOURS * WS-HOURLY-RATE-NUM

      *--- OVERTIME PAY (1.5x RATE) ---
           COMPUTE WS-OVERTIME-PAY =
               WS-OVERTIME-HOURS *
               (WS-HOURLY-RATE-NUM * 1.5)

      *--- GROSS SALARY ---
           COMPUTE WS-GROSS-SALARY =
               WS-REGULAR-PAY + WS-OVERTIME-PAY

      *--- DEDUCTIONS ---
           COMPUTE WS-FED-TAX-AMT =
               WS-GROSS-SALARY * WS-FED-TAX-RATE
           COMPUTE WS-STATE-TAX-AMT =
               WS-GROSS-SALARY * WS-STATE-TAX-RATE
           COMPUTE WS-TOTAL-DEDUCTIONS =
               WS-FED-TAX-AMT + WS-STATE-TAX-AMT
               + WS-INSURANCE-NUM

      *--- NET PAY ---
           COMPUTE WS-NET-PAY =
               WS-GROSS-SALARY - WS-TOTAL-DEDUCTIONS

      *--- UPDATE GRAND TOTALS ---
           ADD WS-GROSS-SALARY TO WS-GRAND-GROSS
           END-ADD
           ADD WS-TOTAL-DEDUCTIONS TO WS-GRAND-DED
           END-ADD
           ADD WS-NET-PAY TO WS-GRAND-NET
           END-ADD
           .

      *================================================================
       0400-WRITE-PAYSLIP.
      *================================================================
           INITIALIZE WS-PAYSLIP-DETAIL
           MOVE TC-EMP-ID TO WS-PD-EMPID
           MOVE WS-ET-NAME(WS-EMP-IDX) TO WS-PD-NAME
           MOVE WS-ET-DEPT(WS-EMP-IDX) TO WS-PD-DEPT
           MOVE WS-HOURS-NUM TO WS-PD-HOURS
           MOVE WS-REGULAR-PAY TO WS-PD-REGPAY
           MOVE WS-OVERTIME-PAY TO WS-PD-OTPAY
           MOVE WS-GROSS-SALARY TO WS-PD-GROSS
           MOVE WS-TOTAL-DEDUCTIONS TO WS-PD-DEDUCT
           MOVE WS-NET-PAY TO WS-PD-NET

           WRITE PR-RECORD FROM WS-PAYSLIP-DETAIL
           END-WRITE
           .

      *================================================================
       0500-UPDATE-DEPT-TOTALS.
      *================================================================
           MOVE 'N' TO WS-DEPT-FOUND

           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-DEPT-COUNT
                  OR WS-DEPT-FOUND = 'Y'
               IF WS-ET-DEPT(WS-EMP-IDX) =
                   WS-DT-DEPT-CODE(WS-I)
                   MOVE 'Y' TO WS-DEPT-FOUND
                   MOVE WS-I TO WS-DEPT-IDX
               END-IF
           END-PERFORM

           IF WS-DEPT-FOUND = 'N'
               ADD 1 TO WS-DEPT-COUNT
               MOVE WS-DEPT-COUNT TO WS-DEPT-IDX
               MOVE WS-ET-DEPT(WS-EMP-IDX) TO
                   WS-DT-DEPT-CODE(WS-DEPT-IDX)
               MOVE ZERO TO
                   WS-DT-HEADCOUNT(WS-DEPT-IDX)
               MOVE ZERO TO
                   WS-DT-TOTAL-GROSS(WS-DEPT-IDX)
               MOVE ZERO TO
                   WS-DT-TOTAL-DED(WS-DEPT-IDX)
               MOVE ZERO TO
                   WS-DT-TOTAL-NET(WS-DEPT-IDX)
           END-IF

           ADD 1 TO WS-DT-HEADCOUNT(WS-DEPT-IDX)
           END-ADD
           ADD WS-GROSS-SALARY TO
               WS-DT-TOTAL-GROSS(WS-DEPT-IDX)
           END-ADD
           ADD WS-TOTAL-DEDUCTIONS TO
               WS-DT-TOTAL-DED(WS-DEPT-IDX)
           END-ADD
           ADD WS-NET-PAY TO
               WS-DT-TOTAL-NET(WS-DEPT-IDX)
           END-ADD
           .

      *================================================================
       0700-WRITE-EXCEPTION.
      *================================================================
           INITIALIZE WS-EXC-DETAIL
           MOVE WS-TIMESTAMP TO WS-ED-TS
           MOVE WS-ERROR-CODE TO WS-ED-RC
           MOVE TC-RECORD TO WS-ED-REC

           EVALUATE WS-ERROR-CODE
               WHEN 'ERR-01'
                   MOVE 'INVALID EMP-ID OR HO'
                       & 'URS (NON-NUMERIC/ZERO)'
                       TO WS-ED-MSG
               WHEN 'ERR-02'
                   MOVE 'EMPLOYEE ID NOT FOUN'
                       & 'D IN MASTER TABLE'
                       TO WS-ED-MSG
               WHEN 'ERR-03'
                   MOVE 'TAX BRACKET CODE NOT'
                       & ' FOUND IN INDEX'
                       TO WS-ED-MSG
               WHEN OTHER
                   MOVE 'UNKNOWN ERROR CONDIT'
                       & 'ION'
                       TO WS-ED-MSG
           END-EVALUATE

           WRITE EL-RECORD FROM WS-EXC-DETAIL
           END-WRITE

           DISPLAY '  ** EXCEPTION: '
               WS-ERROR-CODE
               ' RECORD=[' TC-RECORD ']'
           END-DISPLAY
           .

      *================================================================
       0800-WRITE-TOTALS.
      *================================================================
      *--- WRITE PAYSLIP GRAND TOTALS ---
           MOVE SPACES TO PR-RECORD
           MOVE ALL '-' TO PR-RECORD
           WRITE PR-RECORD
           END-WRITE

           MOVE WS-GRAND-GROSS TO WS-GT-GROSS
           MOVE WS-GRAND-DED TO WS-GT-DED
           MOVE WS-GRAND-NET TO WS-GT-NET
           WRITE PR-RECORD FROM WS-GRAND-TOTAL-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING ' TOTAL RECORDS PROCESSED: '
                  WS-TOTAL-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE PR-RECORD FROM WS-TOTALS-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING '   VALID:  '
                  WS-VALID-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE PR-RECORD FROM WS-TOTALS-LINE
           END-WRITE

           MOVE SPACES TO WS-TOTALS-LINE
           STRING '   ERRORS: '
                  WS-ERROR-RECORDS
                  DELIMITED BY SIZE
                  INTO WS-TOTALS-LINE
           END-STRING
           WRITE PR-RECORD FROM WS-TOTALS-LINE
           END-WRITE

      *--- WRITE DEPARTMENT SUMMARY REPORT ---
           WRITE DS-RECORD FROM WS-DEPT-HDR1
           END-WRITE
           WRITE DS-RECORD FROM WS-DEPT-HDR2
           END-WRITE
           MOVE SPACES TO DS-RECORD
           STRING ' REPORT DATE: ' WS-HDR-DATE
                  DELIMITED BY SIZE INTO DS-RECORD
           END-STRING
           WRITE DS-RECORD
           END-WRITE
           WRITE DS-RECORD FROM WS-DEPT-HDR1
           END-WRITE
           WRITE DS-RECORD FROM WS-DEPT-COL-HDR
           END-WRITE
           MOVE SPACES TO DS-RECORD
           MOVE ALL '-' TO DS-RECORD
           WRITE DS-RECORD
           END-WRITE

           PERFORM VARYING WS-I FROM 1 BY 1
               UNTIL WS-I > WS-DEPT-COUNT
               INITIALIZE WS-DEPT-DETAIL
               MOVE WS-DT-DEPT-CODE(WS-I)
                   TO WS-DD-DEPT
               MOVE WS-DT-HEADCOUNT(WS-I)
                   TO WS-DD-HEAD
               MOVE WS-DT-TOTAL-GROSS(WS-I)
                   TO WS-DD-GROSS
               MOVE WS-DT-TOTAL-DED(WS-I)
                   TO WS-DD-DED
               MOVE WS-DT-TOTAL-NET(WS-I)
                   TO WS-DD-NET
               WRITE DS-RECORD
                   FROM WS-DEPT-DETAIL
               END-WRITE
           END-PERFORM

           MOVE SPACES TO DS-RECORD
           MOVE ALL '=' TO DS-RECORD
           WRITE DS-RECORD
           END-WRITE
           .

      *================================================================
       0900-TERMINATE.
      *================================================================
           CLOSE TIMECARD-FILE
           CLOSE PAYSLIP-REPORT-FILE
           CLOSE DEPT-SUMMARY-FILE
           CLOSE EXCEPTION-LOG-FILE

           DISPLAY '================================='
               '================'
           DISPLAY ' PAYROLL BATCH PROCESSING'
               ' COMPLETE'
           DISPLAY ' TOTAL RECORDS : '
               WS-TOTAL-RECORDS
           DISPLAY ' VALID RECORDS : '
               WS-VALID-RECORDS
           DISPLAY ' ERROR RECORDS : '
               WS-ERROR-RECORDS
           DISPLAY ' RETURN CODE   : RC='
               WS-RETURN-CODE
           DISPLAY '================================='
               '================'

           MOVE WS-RETURN-CODE TO RETURN-CODE
           .
