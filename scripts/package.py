#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 ChaseLab contributors
import argparse,pathlib,shutil,subprocess,plistlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--arch',choices=['arm64','x86_64'],default='arm64');a=p.parse_args()
    app=ROOT/'build'/a.arch/'ChaseLab.app'
    if not app.exists():raise SystemExit('Build the app first.')
    work=ROOT/'build'/('package-'+a.arch);work.mkdir(parents=True,exist_ok=True)
    component=work/'component.pkg';dist=ROOT/'dist';dist.mkdir(exist_ok=True)
    pkg=dist/('ChaseLab-0.15.0-beta.1-'+('AppleSilicon' if a.arch=='arm64' else 'Intel-experimental')+'.pkg')
    payload=work/'payload'
    if payload.exists():shutil.rmtree(payload)
    target=payload/'Applications/ChaseLab.app';target.parent.mkdir(parents=True)
    shutil.copytree(app,target,symlinks=True)
    config=work/'components.plist'
    subprocess.run(['pkgbuild','--analyze','--root',str(payload),str(config)],check=True)
    data=plistlib.loads(config.read_bytes())
    def fix(value):
        if isinstance(value,dict):
            if 'BundleIsRelocatable' in value:value['BundleIsRelocatable']=False
            for child in value.values():fix(child)
        elif isinstance(value,list):
            for child in value:fix(child)
    fix(data);config.write_bytes(plistlib.dumps(data))
    subprocess.run(['pkgbuild','--root',str(payload),'--component-plist',str(config),'--identifier','local.chaselab.installer','--version','0.15.0',str(component)],check=True)
    xml=work/'Distribution.xml'
    xml.write_text('''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
<title>ChaseLab 0.15 beta — paquete de pruebas sin notarizar</title>
<options customize="never" hostArchitectures="'''+a.arch+'''"/>
<volume-check><allowed-os-versions><os-version min="13.0"/></allowed-os-versions></volume-check>
<readme file="Readme.html"/>
<choices-outline><line choice="default"/></choices-outline>
<choice id="default" visible="false"><pkg-ref id="local.chaselab.installer"/></choice>
<pkg-ref id="local.chaselab.installer" version="0.15.0">component.pkg</pkg-ref>
</installer-gui-script>''')
    subprocess.run(['productbuild','--distribution',str(xml),'--resources',str(ROOT/'packaging/macos'),'--package-path',str(work),str(pkg)],check=True)
    print(pkg)
if __name__=='__main__':main()
