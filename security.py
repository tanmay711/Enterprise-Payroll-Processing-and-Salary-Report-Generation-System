"""
Enterprise Payroll System — RACF & SAF Mainframe Security Module
Implements IBM Resource Access Control Facility (RACF), System Authorization
Facility (SAF), SMF Type 80 Security Audit Logging, and Cryptographic Integrity.
"""

import os
import json
import hashlib
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'data')
REF_DIR = os.path.join(DATA_DIR, 'ref')
INPUT_DIR = os.path.join(DATA_DIR, 'input')
OUTPUT_DIR = os.path.join(DATA_DIR, 'output')
INTEGRITY_FILE = os.path.join(REF_DIR, '.dataset_integrity.json')
SMF80_LOG_FILE = os.path.join(OUTPUT_DIR, 'SMF80_SECURITY_AUDIT.log')

# =====================================================================
# RACF USER REPOSITORY & GROUP PROFILES
# Standard IBM Mainframe Security Identifiers
# =====================================================================
RACF_USERS = {
    'IBMUSER': {
        'userid': 'IBMUSER',
        'password': 'SYSADMIN',
        'group': 'SYSADMIN',
        'name': 'Chief Security Officer / SysProg',
        'role': 'Security Administrator',
        'privileges': ['ALTER', 'CONTROL', 'UPDATE', 'READ', 'EXECUTE'],
        'default_auth': 'ALTER'
    },
    'OPER01': {
        'userid': 'OPER01',
        'password': 'OPERATOR',
        'group': 'OPERGRP',
        'name': 'Mainframe Console Operator',
        'role': 'Console Operator',
        'privileges': ['EXECUTE', 'READ'],
        'default_auth': 'EXECUTE'
    },
    'PAYCLRK1': {
        'userid': 'PAYCLRK1',
        'password': 'PAYROLL',
        'group': 'PAYROLL',
        'name': 'Payroll Operations Officer',
        'role': 'Payroll Clerk',
        'privileges': ['UPDATE', 'READ'],
        'default_auth': 'UPDATE'
    },
    'AUDIT01': {
        'userid': 'AUDIT01',
        'password': 'AUDITOR',
        'group': 'AUDITGRP',
        'name': 'Internal Compliance Auditor',
        'role': 'Compliance Auditor',
        'privileges': ['READ'],
        'default_auth': 'READ'
    }
}

# =====================================================================
# RACF ACCESS CONTROL MATRIX (ACL PROFILES)
# Defines RACF Discrete/Generic Profiles and required authorities
# Levels: NONE < READ < UPDATE < CONTROL < ALTER
# =====================================================================
ACCESS_HIERARCHY = {
    'NONE': 0,
    'READ': 1,
    'UPDATE': 2,
    'CONTROL': 3,
    'ALTER': 4,
    'EXECUTE': 2  # Execute treated as update-level capability for facilities
}

RESOURCE_PROFILES = {
    'JOB.PAYPROC01.SUBMIT': {
        'class': 'FACILITY',
        'description': 'Authority to submit JCL batch job PAYPROC01',
        'required': 'EXECUTE',
        'acl': {
            'SYSADMIN': 'ALTER',
            'OPERGRP': 'EXECUTE',
            'PAYROLL': 'NONE',
            'AUDITGRP': 'NONE'
        }
    },
    'DATA.INPUT.TIMECARDS': {
        'class': 'DATASET',
        'description': 'Timecard ingestion dataset (raw_timecards.dat)',
        'required': 'UPDATE',
        'acl': {
            'SYSADMIN': 'ALTER',
            'PAYROLL': 'UPDATE',
            'OPERGRP': 'READ',
            'AUDITGRP': 'READ'
        }
    },
    'DATA.REF.EMPLOYEE.MASTER': {
        'class': 'DATASET',
        'description': 'DB2 Employee Master table dataset',
        'required': 'READ',
        'acl': {
            'SYSADMIN': 'ALTER',
            'PAYROLL': 'READ',
            'OPERGRP': 'READ',
            'AUDITGRP': 'READ'
        }
    },
    'DATA.REF.TAX.RATES': {
        'class': 'DATASET',
        'description': 'VSAM KSDS Tax Rates index dataset',
        'required': 'READ',
        'acl': {
            'SYSADMIN': 'ALTER',
            'PAYROLL': 'READ',
            'OPERGRP': 'READ',
            'AUDITGRP': 'READ'
        }
    },
    'DATA.OUTPUT.REPORTS': {
        'class': 'DATASET',
        'description': 'SYSOUT Payslip, Dept Summary & Exception datasets',
        'required': 'READ',
        'acl': {
            'SYSADMIN': 'ALTER',
            'OPERGRP': 'READ',
            'PAYROLL': 'READ',
            'AUDITGRP': 'READ'
        }
    },
    'SECURITY.RACF.CONFIG': {
        'class': 'FACILITY',
        'description': 'Manage RACF security rules, hashes, and profiles',
        'required': 'ALTER',
        'acl': {
            'SYSADMIN': 'ALTER',
            'OPERGRP': 'NONE',
            'PAYROLL': 'NONE',
            'AUDITGRP': 'NONE'
        }
    }
}


# =====================================================================
# SAF (SYSTEM AUTHORIZATION FACILITY) CHECK FUNCTION
# Mimics IBM RACROUTE REQUEST=AUTH macro
# =====================================================================
def check_authority(userid, resource_name, requested_access='READ'):
    """
    Validates user credentials against RACF Access Control Lists.
    Returns: dict with permitted (bool), saf_rc (int), racf_rc (int), message (str)
    """
    user = RACF_USERS.get(userid)
    if not user:
        result = {
            'permitted': False,
            'saf_rc': 8,
            'racf_rc': 4,
            'reason': 'RACF USERID NOT DEFINED TO SECURITY DATABASE'
        }
        log_smf80_record(userid or 'UNKNOWN', 'AUTH_CHECK', resource_name, requested_access, 'VIOLATION', 8, 4, result['reason'])
        return result

    profile = RESOURCE_PROFILES.get(resource_name)
    if not profile:
        # Default allow if resource not explicitly restricted
        return {'permitted': True, 'saf_rc': 0, 'racf_rc': 0, 'reason': 'DEFAULT PROFILE - ACCESS GRANTED'}

    user_group = user['group']
    granted_level = profile['acl'].get(user_group, 'NONE')
    
    granted_score = ACCESS_HIERARCHY.get(granted_level, 0)
    required_score = ACCESS_HIERARCHY.get(requested_access, 1)

    if granted_score >= required_score:
        result = {
            'permitted': True,
            'saf_rc': 0,
            'racf_rc': 0,
            'reason': f'ACCESS GRANTED (CLASS={profile["class"]} PROFILE={resource_name} LEVEL={granted_level})'
        }
        log_smf80_record(userid, 'AUTH_CHECK', resource_name, requested_access, 'PERMITTED', 0, 0, result['reason'])
        return result
    else:
        result = {
            'permitted': False,
            'saf_rc': 8,
            'racf_rc': 8,
            'reason': f'INSUFFICIENT ACCESS AUTHORITY (REQUIRED={requested_access}, GRANTED={granted_level})'
        }
        log_smf80_record(userid, 'AUTH_CHECK', resource_name, requested_access, 'VIOLATION', 8, 8, result['reason'])
        return result


# =====================================================================
# SMF TYPE 80 SECURITY AUDIT LOGGING
# System Management Facility Type 80 (RACF Processing) Emulation
# =====================================================================
def log_smf80_record(userid, event_type, resource, intent, status, saf_rc, racf_rc, details):
    """
    Appends an SMF Type 80 security event record into the audit dataset.
    """
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    
    # SMF Record Format:
    # [SMF-80] TIMESTAMP | USERID | GROUP | EVENT | RESOURCE | INTENT | STATUS | SAF_RC | RACF_RC | DETAILS
    group = RACF_USERS.get(userid, {}).get('group', 'NOGROUP')
    record = (
        f"[SMF-80] {timestamp} | {userid:<8} | {group:<8} | {event_type:<10} | "
        f"{resource:<24} | {intent:<7} | {status:<9} | RC={saf_rc:04d} | RC={racf_rc:04d} | {details}\n"
    )

    try:
        with open(SMF80_LOG_FILE, 'a', encoding='utf-8') as f:
            f.write(record)
    except Exception as e:
        print(f"Error writing SMF record: {e}")


def get_smf80_logs(limit=50):
    """Read recent SMF Type 80 security audit entries."""
    if not os.path.exists(SMF80_LOG_FILE):
        return []
    
    logs = []
    try:
        with open(SMF80_LOG_FILE, 'r', encoding='utf-8', errors='replace') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
        
        # Parse lines in reverse order (most recent first)
        for line in reversed(lines[-limit:]):
            if line.startswith('[SMF-80]'):
                parts = [p.strip() for p in line[8:].split('|')]
                if len(parts) >= 9:
                    logs.append({
                        'timestamp': parts[0],
                        'userid': parts[1],
                        'group': parts[2],
                        'event': parts[3],
                        'resource': parts[4],
                        'intent': parts[5],
                        'status': parts[6],
                        'saf_rc': parts[7],
                        'racf_rc': parts[8],
                        'details': parts[9] if len(parts) > 9 else ''
                    })
    except Exception as e:
        print(f"Error reading SMF logs: {e}")
    return logs


# =====================================================================
# CRYPTOGRAPHIC DATASET INTEGRITY & PERVASIVE ENCRYPTION HASHES
# SHA-256 Digest Validation of Master Tables
# =====================================================================
def compute_file_sha256(filepath):
    """Compute SHA-256 checksum of a dataset file."""
    if not os.path.exists(filepath):
        return None
    sha = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(4096):
            sha.update(chunk)
    return sha.hexdigest()


def generate_integrity_signatures():
    """Generates baseline cryptographic hashes for protected reference datasets."""
    files_to_protect = {
        'employee_master.dat': os.path.join(REF_DIR, 'employee_master.dat'),
        'tax_rates_index.dat': os.path.join(REF_DIR, 'tax_rates_index.dat')
    }
    
    integrity_manifest = {
        'generated_at': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'algorithm': 'SHA-256',
        'generated_by': 'IBMUSER (RACF SYSADMIN)',
        'datasets': {}
    }

    for name, path in files_to_protect.items():
        if os.path.exists(path):
            digest = compute_file_sha256(path)
            size = os.path.getsize(path)
            integrity_manifest['datasets'][name] = {
                'sha256': digest,
                'bytes': size,
                'status': 'SECURE'
            }

    with open(INTEGRITY_FILE, 'w', encoding='utf-8') as f:
        json.dump(integrity_manifest, f, indent=2)

    log_smf80_record('IBMUSER', 'INTEGRITY', 'DATA.REF.INTEGRITY', 'ALTER', 'PERMITTED', 0, 0, 'CRYPTOGRAPHIC INTEGRITY SIGNATURES GENERATED')
    return integrity_manifest


def verify_dataset_integrity():
    """
    Validates reference files against stored cryptographic baseline hashes.
    Returns: dict with verified (bool), details (list), error (str)
    """
    if not os.path.exists(INTEGRITY_FILE):
        # Auto generate if missing initially
        generate_integrity_signatures()

    try:
        with open(INTEGRITY_FILE, 'r', encoding='utf-8') as f:
            manifest = json.load(f)
    except Exception as e:
        return {'verified': False, 'details': [], 'error': f'Failed to load integrity manifest: {e}'}

    all_verified = True
    details = []

    for name, meta in manifest.get('datasets', {}).items():
        path = os.path.join(REF_DIR, name)
        current_hash = compute_file_sha256(path)
        expected_hash = meta.get('sha256')

        if current_hash is None:
            all_verified = False
            details.append({
                'dataset': name,
                'status': 'MISSING',
                'current_hash': 'NONE',
                'expected_hash': expected_hash,
                'match': False
            })
        elif current_hash != expected_hash:
            all_verified = False
            details.append({
                'dataset': name,
                'status': 'TAMPERED / CORRUPTED',
                'current_hash': current_hash,
                'expected_hash': expected_hash,
                'match': False
            })
            log_smf80_record('SYSTEM', 'INTEGRITY', f'DATA.REF.{name.upper()}', 'READ', 'VIOLATION', 8, 16, f'CHECKSUM MISMATCH DETECTED FOR {name}')
        else:
            details.append({
                'dataset': name,
                'status': 'VERIFIED SECURE',
                'current_hash': current_hash,
                'expected_hash': expected_hash,
                'match': True
            })

    return {
        'verified': all_verified,
        'details': details,
        'manifest_time': manifest.get('generated_at', 'UNKNOWN'),
        'algorithm': manifest.get('algorithm', 'SHA-256')
    }


# =====================================================================
# CLI EXECUTION (CALLED BY JCL STEP00)
# =====================================================================
if __name__ == '__main__':
    import sys
    action = sys.argv[1] if len(sys.argv) > 1 else 'verify'
    userid = sys.argv[2] if len(sys.argv) > 2 else 'IBMUSER'

    if action == 'init':
        generate_integrity_signatures()
        print("RACF: Cryptographic signatures created successfully.")
        sys.exit(0)

    elif action == 'verify':
        print("//STEP00  EXEC PGM=RACFCHK,PARM='VALIDATE INTEGRITY & ACCESS'")
        print("-----------------------------------------------------------")
        print(f"  RACF SUBMITTER IDENTIFIER: {userid}")
        
        # Check authorization to run batch
        auth = check_authority(userid, 'JOB.PAYPROC01.SUBMIT', 'EXECUTE')
        print(f"  SAF STATUS: {auth['reason']}")
        if not auth['permitted']:
            print(f"  ** SECURITY ABEND: SAF RC={auth['saf_rc']:04d} RACF RC={auth['racf_rc']:04d}")
            sys.exit(16)

        # Check dataset integrity
        integrity = verify_dataset_integrity()
        for item in integrity['details']:
            status_symbol = "OK" if item['match'] else "** FAILED **"
            print(f"  DATASET: {item['dataset']:<22} HASH: {item['current_hash'][:16]}... [{status_symbol}]")

        if not integrity['verified']:
            print("  ** SECURITY ABEND: DATASET TAMPERING OR SIGNATURE MISMATCH DETECTED!")
            print("  STEP00 RC=0016")
            sys.exit(16)

        print("  ALL REFERENCE DATASETS CRYPTOGRAPHICALLY VERIFIED")
        print("  SMF TYPE 80 AUDIT RECORD CREATED")
        print("  STEP00 RC=0000")
        print("")
        sys.exit(0)
