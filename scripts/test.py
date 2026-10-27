#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 ChaseLab contributors
import argparse,json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
def run(*args):subprocess.run([str(a) for a in args],cwd=ROOT,check=True)
def main():
    p=argparse.ArgumentParser();p.add_argument('--gpu',action='store_true');a=p.parse_args();build=ROOT/'build/tests';build.mkdir(parents=True,exist_ok=True)
    run('swiftc','-module-cache-path',ROOT/'build/swift-cache','apps/macos/Source/PluginInstallCore.swift','tests/installer/main.swift','-o',build/'installer')
    run(build/'installer')
    run('clang++','-std=c++17','-O2','plugins/random/Tests/RandomEngineTests.cpp','-o',build/'random-engine');run(build/'random-engine')
    app=ROOT/'build/arm64/ChaseLab.app/Contents/MacOS/ChaseLab'
    if app.exists():run(app,'--self-test')
    if a.gpu:
        fixtures=[('player','PlayerTests','ChaseLabPlayer4',[]),('bumper','BumperTests','ChaseLabBumper',[]),('outliner','OutlinerTests','ChaseLabOutliner',['0']),('outliner','OutlinerTests','ChaseLabOutlinerSource',['1']),('wiper','WiperTests','ChaseLabWiper',[]),('random','RandomTests','ChaseLabRandom',[])]
        for component,test,binary,extra in fixtures:
            target=build/test
            run('clang++','-std=c++17','-O2','-DGL_SILENCE_DEPRECATION','-fobjc-arc','-Ithird_party/ffgl/lib',f'plugins/{component}/Tests/{test}.mm','-framework','Foundation','-framework','OpenGL','-o',target)
            run(target,ROOT/f'build/Plugins/{binary}.bundle/Contents/MacOS/{binary}',*extra)
    print('PASS: selected release checks')
if __name__=='__main__':main()
