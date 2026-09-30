"""
Enterprise Payroll System — Web Dashboard
Flask server linking the COBOL batch engine to a browser UI.
"""

import os
import subprocess
import json
from datetime import datetime
from flask import Flask, render_template, jsonify, request

app = Flask(__name__,
            template_folder='templates',
            static_folder='static')

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
    """Return all output reports."""
    payslip = read_report('MONTHLY_PAYSLIP_REPORT.txt')
    dept = read_report('DEPT_PAYROLL_SUMMARY.txt')
    exceptions = read_report('PAYROLL_EXCEPTION_LOG.txt')
    return jsonify({
        'payslip': payslip,
        'dept_summary': dept,
        'exceptions': exceptions,
        'generated_at': get_report_time('MONTHLY_PAYSLIP_REPORT.txt'),
        'has_reports': payslip is not None
    })


@app.route('/api/run', methods=['POST'])
def run_batch():
    """Execute the COBOL payroll batch pipeline via WSL."""
    wsl_path = f"/mnt/d/College Assigments/TY/Mainframe/Cp/payroll-system"
    cmd = f"cd '{wsl_path}' && bash scripts/run_batch.sh 2>&1"

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
    """Save updated timecard data."""
    data = request.json.get('timecards', '')
    filepath = os.path.join(DATA_DIR, 'input', 'raw_timecards.dat')
    try:
        with open(filepath, 'w', encoding='ascii', newline='\n') as f:
            f.write(data)
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})


if __name__ == '__main__':
    print("=" * 55)
    print("  ENTERPRISE PAYROLL SYSTEM — WEB DASHBOARD")
    print("  Open http://localhost:5000 in your browser")
    print("=" * 55)
    app.run(debug=True, port=5000)
