// SPDX-License-Identifier: Apache-2.0
using ChaseLab;
using System.Text.Json.Nodes;
void Require(bool value,string name){if(!value)throw new Exception(name);Console.WriteLine("PASS "+name);}
void Reject(Action action,string name){try{action();}catch{Console.WriteLine("PASS "+name);return;}throw new Exception("Expected rejection: "+name);}
var p=Project.Read(args[0]);string original=p.Data.ToJsonString();string dir=Path.Combine(Path.GetTempPath(),"chaselab-checks-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
try{
 p.Data["futureOptional"]="preserved";string file=Path.Combine(dir,"roundtrip.chaselab");p.Save(file);var q=Project.Read(file);Require(JsonNode.DeepEquals(p.Data,q.Data),"Mac schema roundtrip preserves unknown fields");
 p.SetWeight(0,0,2);Require(p.Position(0,.75).step==0&&Math.Abs(p.Position(0,.75).phase-.75)<1e-9,"weighted timing inside step");Require(p.Position(0,1).step==1,"weighted timing boundary");
 p.Resize(0,5);Require(p.Count(0)==5&&p.Weight(0,4)==1,"append step and duration");p.Resize(0,2);Require(p.Count(0)==2&&p.Weight(0,0)==2,"remove step preserves preceding duration");p.Save(file);
 foreach(var env in new[]{"Corte","Fade out","Pulso"}){p.Envelope=env;Require(Enumerable.Range(0,101).All(i=>double.IsFinite(p.Level(i/100d))&&p.Level(i/100d)>=0&&p.Level(i/100d)<=1),"bounded envelope "+env);}
 var invalid=JsonNode.Parse(original)!.AsObject();invalid["sequences"]![0]!["durations"]=new JsonArray(0,1,1,1);Reject(()=>new Project(invalid),"reject invalid duration");
 string xml=Path.Combine(dir,"input.xml");File.WriteAllText(xml,"<root><CurrentCompositionTextureSize width='1024' height='576'/><Slice><Params name='Common'><Param name='Name' value='A'/></Params><InputRect><v x='0' y='0'/><v x='100' y='0'/><v x='0' y='100'/></InputRect></Slice></root>");var imported=Project.ImportXml(xml);Require(imported.Width==1024&&imported.Height==576&&imported.Slices.Count==1&&!imported.Cell(0,0,0),"XML input polygon import and empty sequence");File.WriteAllText(xml,"<!DOCTYPE r [<!ENTITY ext SYSTEM 'file:///etc/passwd'>]><r>&ext;</r>");Reject(()=>Project.ImportXml(xml),"reject XML DTD/external entities");
 p.Save(file);Require(Directory.GetFiles(dir,"*.tmp").Length==0,"atomic save leaves no partial files");
}finally{Directory.Delete(dir,true);}
