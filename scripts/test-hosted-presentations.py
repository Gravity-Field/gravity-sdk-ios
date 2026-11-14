#!/usr/bin/env python3
"""Build an isolated app host and run real UIKit presentation regressions.
Usage: python3 scripts/test-hosted-presentations.py SIMULATOR_UUID OUTPUT_DIR [all|steps|cancellation|impressions]
The supplied simulator must already be booted. Nothing outside loopback is allowed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

sim, output = sys.argv[1:3]
mode = sys.argv[3] if len(sys.argv) > 3 else 'all'
repo = Path(__file__).resolve().parents[1]
out = Path(output).resolve()
out.mkdir(parents=True, exist_ok=True)
project = out.parent / 'hosted-app'
if project.exists():
    shutil.rmtree(project)
project.mkdir()
shutil.copytree(repo / 'Example/GravitySDKDemo/GravitySDKDemo.xcodeproj', project / 'GravitySDKDemo.xcodeproj')
source = project / 'GravitySDKDemo'
source.mkdir()
for file in (repo / 'Tests/HostedPresentationTests').glob('*.swift'):
    shutil.copy(file, source)
shutil.copy(repo / 'Tests/GravitySDKTests/RecordingServer.swift', source)
shutil.copy(repo / 'Tests/NetworkTestGuard/NetworkTestGuard.m', source)
shutil.copy(repo / 'Tests/NetworkTestGuard/include/NetworkTestGuard.h', source)
(source / 'Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict></dict></plist>''')
pbx = project / 'GravitySDKDemo.xcodeproj/project.pbxproj'
text = pbx.read_text().replace('../../../gravity-sdk-ios', str(repo))
text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 17.0;', text)
bundle = 'ai.gravityfield.HostedPresentationTests'
text = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;', f'PRODUCT_BUNDLE_IDENTIFIER = {bundle};', text)
pbx.write_text(text)
commands = []

def run(args, **kwargs):
    commands.append(args)
    (out / 'commands.json').write_text(json.dumps(commands, indent=2))
    return subprocess.run(args, check=True, **kwargs)

with (out / 'build.log').open('w') as log:
    run(['xcodebuild', 'build', '-project', str(pbx.parent), '-scheme', 'GravitySDKDemo',
         '-destination', f'platform=iOS Simulator,id={sim}', '-derivedDataPath', str(out.parent / 'hosted-derived'),
         'CODE_SIGNING_ALLOWED=NO'], stdout=log, stderr=subprocess.STDOUT)
app = out.parent / 'hosted-derived/Build/Products/Debug-iphonesimulator/GravitySDKDemo.app'
run(['xcrun', 'simctl', 'install', sim, str(app)])
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', sim, bundle, 'data'], text=True).strip())
docs = container / 'Documents'
docs.mkdir(exist_ok=True)
for name in ['hosted-results.json', 'background-request', 'hosted.log']:
    (docs / name).unlink(missing_ok=True)
env = dict(os.environ, SIMCTL_CHILD_HOSTED_TEST_MODE=mode)
run(['xcrun', 'simctl', 'launch', '--terminate-running-process', sim, bundle], env=env)
deadline = time.monotonic() + 360
while time.monotonic() < deadline:
    if (docs / 'background-request').exists():
        (docs / 'background-request').unlink()
        time.sleep(1)
        run(['xcrun', 'simctl', 'launch', sim, bundle], stdout=subprocess.DEVNULL)
    if (docs / 'hosted-results.json').exists():
        shutil.copy(docs / 'hosted-results.json', out)
        shutil.copy(docs / 'hosted.log', out)
        result = json.loads((out / 'hosted-results.json').read_text())
        print(json.dumps(result, indent=2))
        sys.exit(1 if result['failures'] else 0)
    time.sleep(0.02)
if (docs / 'hosted.log').exists():
    shutil.copy(docs / 'hosted.log', out)
raise SystemExit('Hosted tests timed out; inspect build.log and hosted.log')
