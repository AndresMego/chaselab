#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 ChaseLab contributors
import argparse, hashlib, json, pathlib, plistlib, shutil, subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
VERSION='0.15.0-beta.1'
def run(*args): subprocess.run([str(a) for a in args],check=True,cwd=ROOT)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--arch',choices=['arm64','x86_64'],default='arm64');parser.add_argument('--skip-plugins',action='store_true');args=parser.parse_args()
    build=ROOT/'build';plugins=build/'Plugins';plugins.mkdir(parents=True,exist_ok=True)
    components=json.loads((ROOT/'packaging/components.json').read_text())
    for c in components:
        bundle=plugins/(c['binary']+'.bundle');binary=bundle/'Contents/MacOS'/c['binary']
        if not args.skip_plugins or not binary.exists():
            binary.parent.mkdir(parents=True,exist_ok=True)
            run('clang++','-std=c++17','-O2','-DNDEBUG','-DGL_SILENCE_DEPRECATION',f"-DSOURCE_MODE={c['sourceMode']}",'-fobjc-arc','-arch','arm64','-arch','x86_64','-mmacosx-version-min=13.0','-Ithird_party/ffgl/lib','-dynamiclib','third_party/ffgl/lib/FFGLSDK.cpp',f"plugins/{c['component']}/FFGL/{c['source']}",'-framework','Foundation','-framework','OpenGL','-o',binary)
            (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable=c['binary'],CFBundleIdentifier=c['bundleID'],CFBundleName=c['name'],CFBundlePackageType='BNDL',CFBundleShortVersionString=c['version'])))
            run('codesign','--force','--sign','-',bundle)
        run('codesign','--verify','--strict',bundle)
    app=build/args.arch/'ChaseLab.app';macos=app/'Contents/MacOS';macos.mkdir(parents=True,exist_ok=True)
    sources=sorted(f for f in (ROOT/'apps/macos/Source').rglob('*.swift') if f.name not in ['arena-clock.swift','verify-timed-video.swift'])
    run('swiftc','-target',args.arch+'-apple-macos13.0','-module-cache-path',build/'swift-cache','-O',*sources,'-o',macos/'ChaseLab')
    resources=app/'Contents/Resources';resources.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'apps/macos/Source/Assets/ChaseLab.icns',resources/'ChaseLab.icns')
    shutil.copytree(plugins,resources/'Plugins',dirs_exist_ok=True)
    manifest=[]
    for c in components:
        manifest.append(dict(filename=c['binary']+'.bundle',name=c['name'],id=c['id'],bundleID=c['bundleID'],binary=c['binary'],sha256=hashlib.sha256((plugins/(c['binary']+'.bundle/Contents/MacOS')/c['binary']).read_bytes()).hexdigest()))
    (resources/'plugins.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for f in ['LICENSE','NOTICE','THIRD_PARTY_NOTICES.md']:shutil.copy2(ROOT/f,resources/f)
    shutil.copy2(ROOT/'third_party/ffgl/LICENSE.md',resources/'FFGL-LICENSE.md')
    (app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='ChaseLab',CFBundleName='ChaseLab',CFBundleDisplayName='ChaseLab',CFBundleIdentifier='local.chaselab.live.app',CFBundleIconFile='ChaseLab',CFBundlePackageType='APPL',CFBundleShortVersionString='0.15.0',CFBundleVersion='1501',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True)))
    run('codesign','--force','--sign','-',app);run('codesign','--verify','--deep','--strict',app)
    print(app)
if __name__=='__main__':main()
