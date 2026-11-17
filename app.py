"""
Enterprise Payroll System — Web Dashboard
Flask server linking the COBOL batch engine to a browser UI.
"""

import os
import subprocess
import json
from datetime import datetime
from flask import Flask, render_template, jsonify, request, session
import security

app = Flask(__name__,
            template_folder='templates',
            static_folder='static')
app.secret_key = 'ibm-mainframe-racf-saf-secret-key-2026'


def get_current_user():
    """Retrieve active RACF identity from headers, session, or default."""
    userid = request.headers.get('X-RACF-User') or session.get('racf_user') or 'IBMUSER'
    if userid not in security.RACF_USERS:
        userid = 'IBMUSER'
    return userid

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.join(BASE_DIR)
DATA_DIR = os.path.join(PROJECT_DIR, 'data')


def read_file_lines(filepath):
    """Read a file and return its lines, stripping CR."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            return [line.rstrip('\r\n') for line in f.readlines() if line.strip()]
    except FileNotFoundError:
        return []


def parse_employees():
    """Parse employee_master.dat into structured data."""
    lines = read_file_lines(os.path.join(DATA_DIR, 'ref', 'employee_master.dat'))
    employees = []
    for line in lines:
        if len(line) >= 39:
            employees.append({
                'id': line[0:5].strip(),
                'name': line[5:25].strip(),
                'dept': line[25:29].strip(),
                'rate': f"{int(line[29:34]) / 100:.2f}",
                'insurance': f"{int(line[34:39]) / 100:.2f}"
            })
    return employees


def parse_tax_rates():
    """Parse tax_rates_index.dat into structured data."""
    lines = read_file_lines(os.path.join(DATA_DIR, 'ref', 'tax_rates_index.dat'))
    rates = []
    for line in lines:
        if len(line) >= 7:
            rates.append({
                'bracket': line[0],
                'state': f"{int(line[1:4]) / 100:.0%}",
                'federal': f"{int(line[4:7]) / 100:.0%}"
            })
    return rates


def parse_timecards():
    """Parse raw_timecards.dat into structured data."""
    lines = read_file_lines(os.path.join(DATA_DIR, 'input', 'raw_timecards.dat'))
    cards = []
    for line in lines:
        if len(line) >= 9:
            emp_id = line[0:5]
            hours_raw = line[5:8]
            bracket = line[8]
            try:
                hours = int(hours_raw) / 10
                hours_str = f"{hours:.1f}"
            except ValueError:
                hours_str = hours_raw
            cards.append({
                'emp_id': emp_id,
                'hours': hours_str,
                'bracket': bracket
            })
    return cards


def read_report(filename):
    """Read an output report file."""
    filepath = os.path.join(DATA_DIR, 'output', filename)
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            return f.read()
    except FileNotFoundError:
        return None


def get_report_time(filename):
    """Get the last modified time of a report file."""
    filepath = os.path.join(DATA_DIR, 'output', filename)
    try:
        mtime = os.path.getmtime(filepath)
        return datetime.fromtimestamp(mtime).strftime('%Y-%m-%d %H:%M:%S')
    except FileNotFoundError:
        return None


def parse_dept_summary():
    """Parse DEPT_PAYROLL_SUMMARY.txt into structured list."""
    content = read_report('DEPT_PAYROLL_SUMMARY.txt')
    if not content:
        return []
    depts = []
    lines = content.splitlines()
    for line in lines:
        parts = line.strip().split()
        if len(parts) == 5 and parts[0] in ['HR', 'FIN', 'ENG', 'MKT']:
            try:
                depts.append({
                    'dept': parts[0],
                    'headcount': int(parts[1]),
                    'gross': float(parts[2].replace(',', '')),
                    'deduct': float(parts[3].replace(',', '')),
                    'net': float(parts[4].replace(',', ''))
                })
            except ValueError:
                continue
    return depts


def parse_payslip_report():
    """Parse MONTHLY_PAYSLIP_REPORT.txt into structured employee list and totals."""
    content = read_report('MONTHLY_PAYSLIP_REPORT.txt')
    if not content:
        return {'slips': [], 'totals': {}}
    slips = []
    totals = {}
    lines = content.splitlines()
    for line in lines:
        s = line.strip()
        if not s or s.startswith('='):
            continue
        if s.startswith('GRAND TOTALS:'):
            parts = s.replace('GRAND TOTALS:', '').strip().split()
            if len(parts) >= 3:
                try:
                    totals['gross'] = float(parts[0].replace(',', ''))
                    totals['deduct'] = float(parts[1].replace(',', ''))
                    totals['net'] = float(parts[2].replace(',', ''))
                except ValueError:
                    pass
        elif s.startswith('TOTAL RECORDS PROCESSED:'):
            val = s.split(':')[-1].strip()
            totals['total_records'] = int(val) if val.isdigit() else val
        elif s.startswith('VALID:'):
            val = s.split(':')[-1].strip()
            totals['valid_records'] = int(val) if val.isdigit() else val
        elif s.startswith('ERRORS:'):
            val = s.split(':')[-1].strip()
            totals['error_records'] = int(val) if val.isdigit() else val
        else:
            parts = s.split()
            if len(parts) >= 8 and parts[0].isdigit() and len(parts[0]) == 5:
                try:
                    emp_id = parts[0]
                    dept = parts[-7]
                    name = ' '.join(parts[1:-7])
                    hours = float(parts[-6].replace(',', ''))
                    reg_pay = float(parts[-5].replace(',', ''))
                    ot_pay = float(parts[-4].replace(',', ''))
                    gross = float(parts[-3].replace(',', ''))
                    deduct = float(parts[-2].replace(',', ''))
                    net = float(parts[-1].replace(',', ''))
                    slips.append({
                        'id': emp_id,
                        'name': name,
                        'dept': dept,
                        'hours': hours,
                        'reg_pay': reg_pay,
                        'ot_pay': ot_pay,
                        'gross': gross,
                        'deduct': deduct,
                        'net': net
                    })
                except (ValueError, IndexError):
                    continue
    return {'slips': slips, 'totals': totals}


def parse_exception_log():
    """Parse PAYROLL_EXCEPTION_LOG.txt into structured exceptions."""
    content = read_report('PAYROLL_EXCEPTION_LOG.txt')
    if not content:
        return []
    exceptions = []
    lines = content.splitlines()
    for line in lines:
        s = line.strip()
        if not s or s.startswith('=') or s.startswith('-') or s.startswith('TIMESTAMP') or s.startswith('PAYROLL'):
            continue
        parts = s.split()
        if len(parts) >= 4 and parts[2].startswith('ERR-'):
            ts = f"{parts[0]} {parts[1]}"
            rc = parts[2]
            raw_rec = parts[-1]
            desc = " ".join(parts[3:-1])
            exceptions.append({
                'timestamp': ts,
                'rc': rc,
                'desc': desc,
                'raw': raw_rec
            })
    return exceptions


def get_analytics_data():
    """Compile comprehensive analytics for charts."""
    dept_summary = parse_dept_summary()
    payslip_data = parse_payslip_report()
    exceptions = parse_exception_log()
    
    # Calculate OT totals and dept OT breakdown
    total_reg = sum(s['reg_pay'] for s in payslip_data['slips'])
    total_ot = sum(s['ot_pay'] for s in payslip_data['slips'])
    
    dept_ot = {}
    for s in payslip_data['slips']:
        d = s['dept']
        if d not in dept_ot:
            dept_ot[d] = {'reg': 0.0, 'ot': 0.0}
        dept_ot[d]['reg'] += s['reg_pay']
        dept_ot[d]['ot'] += s['ot_pay']
    
    # Error code breakdown
    err_counts = {}
    for e in exceptions:
        code = e['rc']
        err_counts[code] = err_counts.get(code, 0) + 1

    return {
        'departments': dept_summary,
        'employees': payslip_data['slips'],
        'totals': payslip_data['totals'],
        'total_reg_pay': total_reg,
        'total_ot_pay': total_ot,
        'dept_ot': dept_ot,
        'exceptions': exceptions,
        'error_counts': err_counts
    }


@app.route('/')
def dashboard():
    return render_template('dashboard.html')


@app.route('/api/data')
def get_data():
    """Return all input/reference data."""
    return jsonify({
        'employees': parse_employees(),
        'tax_rates': parse_tax_rates(),
        'timecards': parse_timecards()
    })


@app.route('/api/reports')
def get_reports():
    """Return all output reports and structured analytics."""
    payslip = read_report('MONTHLY_PAYSLIP_REPORT.txt')
    dept = read_report('DEPT_PAYROLL_SUMMARY.txt')
    exceptions = read_report('PAYROLL_EXCEPTION_LOG.txt')
    analytics = get_analytics_data()
    return jsonify({
        'payslip': payslip,
        'dept_summary': dept,
        'exceptions': exceptions,
        'analytics': analytics,
        'generated_at': get_report_time('MONTHLY_PAYSLIP_REPORT.txt'),
        'has_reports': payslip is not None
    })


@app.route('/api/analytics')
def get_analytics():
    """Dedicated endpoint for charts and graphs."""
    return jsonify(get_analytics_data())


# =====================================================================
# RACF & SAF SECURITY API ENDPOINTS
# =====================================================================
@app.route('/api/auth/users')
def get_auth_users():
    """Return public metadata of predefined RACF identities."""
    users_info = []
    for uid, u in security.RACF_USERS.items():
        users_info.append({
            'userid': u['userid'],
            'name': u['name'],
            'group': u['group'],
            'role': u['role'],
            'default_auth': u['default_auth'],
            'privileges': u['privileges']
        })
    return jsonify(users_info)


@app.route('/api/auth/current')
def get_current_user_info():
    """Return currently active RACF user profile and permissions."""
    uid = get_current_user()
    user = security.RACF_USERS.get(uid, security.RACF_USERS['IBMUSER'])
    return jsonify({
        'user': user,
        'can_submit': security.check_authority(uid, 'JOB.PAYPROC01.SUBMIT', 'EXECUTE')['permitted'],
        'can_edit_timecards': security.check_authority(uid, 'DATA.INPUT.TIMECARDS', 'UPDATE')['permitted'],
        'can_admin': security.check_authority(uid, 'SECURITY.RACF.CONFIG', 'ALTER')['permitted']
    })


@app.route('/api/auth/switch', methods=['POST'])
def switch_user():
    """Switch active RACF session identity."""
    req_uid = request.json.get('userid', '').strip().upper()
    if req_uid in security.RACF_USERS:
        session['racf_user'] = req_uid
        security.log_smf80_record(req_uid, 'LOGON', 'TSO.TERMINAL', 'CONTROL', 'PERMITTED', 0, 0, f'USER {req_uid} LOGGED ON TO SESSION')
        return jsonify({'success': True, 'userid': req_uid, 'user': security.RACF_USERS[req_uid]})
    return jsonify({'success': False, 'error': 'Invalid RACF User ID'}), 400


@app.route('/api/security/status')
def get_security_status():
    """Return RACF security profiles, access matrix, and dataset integrity check."""
    integrity = security.verify_dataset_integrity()
    return jsonify({
        'users': security.RACF_USERS,
        'resource_profiles': security.RESOURCE_PROFILES,
        'integrity': integrity,
        'current_user': get_current_user()
    })


@app.route('/api/security/smf-logs')
def get_smf_logs():
    """Return recent SMF Type 80 security audit entries."""
    limit = int(request.args.get('limit', 100))
    return jsonify({'logs': security.get_smf80_logs(limit)})


@app.route('/api/security/rehash', methods=['POST'])
def rehash_datasets():
    """Regenerate cryptographic baseline hashes (requires ALTER on SECURITY.RACF.CONFIG)."""
    uid = get_current_user()
    auth = security.check_authority(uid, 'SECURITY.RACF.CONFIG', 'ALTER')
    if not auth['permitted']:
        return jsonify({
            'success': False,
            'error': f"SAF RC={auth['saf_rc']:04d}: Insufficient authority to re-hash security manifest"
        }), 403
    
    manifest = security.generate_integrity_signatures()
    return jsonify({'success': True, 'manifest': manifest})


# =====================================================================
# BATCH EXECUTION & DATA WRITES (SAF PROTECTED)
# =====================================================================
@app.route('/api/run', methods=['POST'])
def run_batch():
    """Execute the COBOL payroll batch pipeline via WSL with RACF authorization check."""
    userid = get_current_user()

    # 1. First Gate: SAF / RACF Authority Verification
    auth = security.check_authority(userid, 'JOB.PAYPROC01.SUBMIT', 'EXECUTE')
    if not auth['permitted']:
        err_msg = (
            f"//STEP00  EXEC PGM=RACFCHK,PARM='VALIDATE INTEGRITY & ACCESS'\n"
            f"-----------------------------------------------------------\n"
            f"  RACF SUBMITTER IDENTIFIER: {userid}\n"
            f"  SAF STATUS: {auth['reason']}\n"
            f"  ** SECURITY ABEND: SAF RC={auth['saf_rc']:04d} RACF RC={auth['racf_rc']:04d}\n"
            f"=========================================================\n"
            f" ** JOB ABENDED IN STEP00: RACF SECURITY VIOLATION\n"
            f" MAXIMUM RETURN CODE: RC=0016\n"
            f" SMF TYPE 80 AUDIT RECORD CREATED (STATUS=VIOLATION)\n"
            f"========================================================="
        )
        return jsonify({
            'success': False,
            'return_code': 16,
            'output': err_msg,
            'security_violation': True,
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        })

    # 2. Execution with authorized UserID passed to JCL
    wsl_path = f"/mnt/d/College Assigments/TY/Mainframe/Cp/payroll-system"
    cmd = f"cd '{wsl_path}' && bash scripts/run_batch.sh {userid} 2>&1"

    try:
        result = subprocess.run(
            ['wsl', '-d', 'Ubuntu', '--', 'bash', '-c', cmd],
            capture_output=True, text=True, timeout=120,
            cwd=PROJECT_DIR
        )
        return jsonify({
            'success': result.returncode == 0,
            'return_code': result.returncode,
            'output': result.stdout + result.stderr,
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        })
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'return_code': -1,
            'output': 'ERROR: Batch job timed out after 120 seconds',
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'return_code': -1,
            'output': f'ERROR: {str(e)}',
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        })


@app.route('/api/timecards', methods=['POST'])
def save_timecards():
    """Save updated timecard data with RACF authorization check."""
    userid = get_current_user()

    # Check UPDATE authority on DATA.INPUT.TIMECARDS
    auth = security.check_authority(userid, 'DATA.INPUT.TIMECARDS', 'UPDATE')
    if not auth['permitted']:
        return jsonify({
            'success': False,
            'error': f"SAF RC={auth['saf_rc']:04d} RACF RC={auth['racf_rc']:04d}: User '{userid}' lacks UPDATE authority on DATA.INPUT.TIMECARDS"
        }), 403

    data = request.json.get('timecards', '')
    filepath = os.path.join(DATA_DIR, 'input', 'raw_timecards.dat')
    try:
        with open(filepath, 'w', encoding='ascii', newline='\n') as f:
            f.write(data)
        security.log_smf80_record(userid, 'DATA_UPDATE', 'DATA.INPUT.TIMECARDS', 'UPDATE', 'PERMITTED', 0, 0, 'TIMECARDS DATASET MODIFIED')
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


if __name__ == '__main__':
    print("=" * 55)
    print("  ENTERPRISE PAYROLL SYSTEM — WEB DASHBOARD")
    print("  Open http://localhost:5000 in your browser")
    print("=" * 55)
    app.run(debug=True, port=5000)
