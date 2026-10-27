// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
import Foundation
import CryptoKit
let fm=FileManager.default
let root=fm.temporaryDirectory.appendingPathComponent("chaselab-install-test-"+UUID().uuidString)
try fm.createDirectory(at:root,withIntermediateDirectories:true)
defer {try? fm.removeItem(at:root)}
let payload=root.appendingPathComponent("payload"),destination=root.appendingPathComponent("effects"),backups=root.appendingPathComponent("backups")
func fixture(_ base:URL,_ text:String,_ id:String)throws {
 let dir=base.appendingPathComponent("Test.bundle/Contents/MacOS");try fm.createDirectory(at:dir,withIntermediateDirectories:true)
 try Data(text.utf8).write(to:dir.appendingPathComponent("Test"))
 try PropertyListSerialization.data(fromPropertyList:["CFBundleIdentifier":id,"CFBundleExecutable":"Test"],format:.xml,options:0).write(to:base.appendingPathComponent("Test.bundle/Contents/Info.plist"))
}
func contents(_ base:URL)throws->String {try String(contentsOf:base.appendingPathComponent("Test.bundle/Contents/MacOS/Test"))}
func fails(_ block:()throws->Void){do {try block();fatalError("Expected rejection")}catch{}}
try fixture(payload,"new","local.chaselab.test");try fixture(destination,"old","local.chaselab.test")
try Data("preserve".utf8).write(to:destination.appendingPathComponent("Unrelated.txt"))
let hash=SHA256.hash(data:Data("new".utf8)).map{String(format:"%02x",$0)}.joined()
let component=PluginComponent(filename:"Test.bundle",name:"Test",id:"TEST",bundleID:"local.chaselab.test",binary:"Test",sha256:hash)
let backup=try PluginInstallCore.install(components:[component],payload:payload,destination:destination,backups:backups)
precondition(try! contents(destination)=="new");precondition(try! contents(backup)=="old");precondition(try! String(contentsOf:destination.appendingPathComponent("Unrelated.txt"))=="preserve")
try fixture(destination,"third-party","other.vendor")
fails {_ = try PluginInstallCore.install(components:[component],payload:payload,destination:destination,backups:backups)}
precondition(try! contents(destination)=="third-party")
try fixture(destination,"keep","local.chaselab.test");try fixture(payload,"tampered","local.chaselab.test")
fails {_ = try PluginInstallCore.install(components:[component],payload:payload,destination:destination,backups:backups)}
precondition(try! contents(destination)=="keep")
try fixture(payload,"new","local.chaselab.test")
let blocked=root.appendingPathComponent("blocked");try Data().write(to:blocked)
fails {_ = try PluginInstallCore.install(components:[component],payload:payload,destination:destination,backups:blocked)}
precondition(try! contents(destination)=="keep")
let traversal=PluginComponent(filename:"../Test.bundle",name:"Test",id:"TEST",bundleID:"local.chaselab.test",binary:"Test",sha256:hash)
fails {_ = try PluginInstallCore.install(components:[traversal],payload:payload,destination:destination,backups:backups)}
print("PASS: install, backup, unrelated-file preservation, identity/hash/path rejection, failed backup leaves installed files untouched")
