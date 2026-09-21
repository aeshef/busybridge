#!/usr/bin/env python3
"""Installation, explicit configuration and launchd. Never reads source events."""
import argparse
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import uuid

os.umask(0o077)
HOME_DIR = pathlib.Path.home()
ROOT = HOME_DIR / 'Library/Application Support/BusyBridge'
APP = HOME_DIR / 'Applications/BusyBridge.app'
PLIST = HOME_DIR / 'Library/LaunchAgents/local.busybridge.calendar.plist'
LABEL = f'gui/{os.getuid()}/local.busybridge.calendar'

def run(mode, *args):
    result = ROOT / f'{mode}-result.json'
    result.unlink(missing_ok=True)
    try:
        subprocess.run(['/usr/bin/open', '-W', '-n', '-g', str(APP), '--args', mode, *args], timeout=60, check=False)
    except subprocess.TimeoutExpired:
        if not result.exists():
            raise SystemExit('No result: check BusyBridge Calendar permission. Do not retry writes blindly.')
    if not result.exists():
        raise SystemExit('No result from application; inspect before retrying.')
    data = json.loads(result.read_text())
    print(json.dumps(data, ensure_ascii=False, indent=2))
    if data.get('status') == 'error':
        raise SystemExit(1)
    return data

parser = argparse.ArgumentParser()
parser.add_argument('command', choices=['install', 'authorize', 'list', 'create-target', 'configure', 'preview', 'sync', 'enable', 'disable', 'status'])
parser.add_argument('--source', action='append', default=[])
parser.add_argument('--target')
parser.add_argument('--account')
parser.add_argument('--include-all-day', action='store_true')
args = parser.parse_args()
ROOT.mkdir(parents=True, exist_ok=True)
if args.command == 'install':
    if APP.exists():
        raise SystemExit('App already installed; stop agent and review before replacing its permission identity.')
    APP.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(pathlib.Path(__file__).parent / 'build/BusyBridge.app', APP)
    print('Installed. Run authorize next.')
elif args.command == 'configure':
    if not args.target or not args.account or not args.source or args.target in args.source:
        raise SystemExit('Explicit --target, --account and --source IDs required; target cannot be a source.')
    cfg_path = ROOT / 'config.json'
    if cfg_path.exists():
        raise SystemExit('Configuration exists. Disable agent and review migration before replacing it.')
    cfg = dict(sourceIDs=args.source, targetID=args.target, targetSourceID=args.account,
               days=60, includeAllDay=args.include_all_day, owner=str(uuid.uuid4()))
    cfg_path.write_text(json.dumps(cfg, indent=2))
    print('Configured. Run preview before sync; all-day inclusion:', args.include_all_day)
elif args.command == 'create-target':
    if not args.account:
        raise SystemExit('--account source ID is required')
    run('create-target', args.account)
elif args.command == 'enable':
    last = ROOT / 'sync-result.json'
    if not last.exists() or json.loads(last.read_text()).get('status') != 'synced_locally':
        raise SystemExit('A successful manual sync is required before enabling background operation.')
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    config = {'Label': 'local.busybridge.calendar',
              'ProgramArguments': ['/usr/bin/open', '-W', '-n', '-g', str(APP), '--args', 'sync'],
              'StartInterval': 300, 'RunAtLoad': True, 'ProcessType': 'Background',
              'LimitLoadToSessionType': 'Aqua', 'ThrottleInterval': 60}
    PLIST.write_bytes(plistlib.dumps(config))
    subprocess.run(['launchctl', 'bootstrap', f'gui/{os.getuid()}', str(PLIST)], check=True)
    print('Enabled every 5 minutes while logged in and awake.')
elif args.command == 'disable':
    subprocess.run(['launchctl', 'bootout', LABEL], check=False)
    PLIST.unlink(missing_ok=True)
    print('Disabled. Existing placeholders remain.')
elif args.command == 'status':
    last = ROOT / 'sync-result.json'
    print(last.read_text() if last.exists() else 'No sync has run.')
    subprocess.run(['launchctl', 'print', LABEL], check=False)
else:
    run(args.command)
