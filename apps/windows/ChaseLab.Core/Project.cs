// SPDX-License-Identifier: Apache-2.0
using System.Text.Json.Nodes;
using System.Xml;
using System.Xml.Linq;
using System.Globalization;
namespace ChaseLab;
public sealed class Project {
 public JsonObject Data {get;}
 public JsonArray Slices => Data["slices"]!.AsArray();
 public JsonArray Sequences => Data["sequences"]!.AsArray();
 public double Width => Data["width"]!.GetValue<double>();
 public double Height => Data["height"]!.GetValue<double>();
 public double Bpm {get=>Data["bpm"]!.GetValue<double>();set=>Data["bpm"]=Math.Clamp(value,20,300);}
 public double Division => Data["division"]!.GetValue<double>();
 public string Envelope {get=>Data["envelope"]!.GetValue<string>();set=>Data["envelope"]=value;}
 public JsonArray Cells(int sequence) => Sequences[sequence]!["cells"]!.AsArray();
 public int Count(int sequence) => Cells(sequence)[0]!.AsArray().Count;
 public bool Cell(int s,int r,int c) => Cells(s)[r]![c]!.GetValue<bool>();
 public void SetCell(int s,int r,int c,bool value) => Cells(s)[r]![c]=value;
 public double Weight(int s,int c) => Sequences[s]?["durations"]?[c]?.GetValue<double>() ?? 1;
 public Project(JsonObject data){Data=data;Validate();}
 public static Project Read(string path){if(new FileInfo(path).Length>20_000_000)throw new InvalidDataException("Proyecto mayor de 20 MB.");return new(JsonNode.Parse(File.ReadAllText(path))!.AsObject());}
 public void Save(string path){Validate();AtomicWrite(path,Data.ToJsonString());}
 public static void AtomicWrite(string path,string text){Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";try{File.WriteAllText(temp,text);File.Move(temp,path,true);}finally{if(File.Exists(temp))File.Delete(temp);}}
 static double Number(JsonNode? n)=>n?.GetValue<double>()??double.NaN;
 public void Validate(){
  int version=Data["version"]?.GetValue<int>()??0;
  if(version<1||version>5||!double.IsFinite(Width)||!double.IsFinite(Height)||Width<=0||Height<=0||Width>16384||Height>16384||!double.IsFinite(Bpm)||Bpm<20||Bpm>300||!new[]{1d,2d,4d}.Contains(Division))throw new InvalidDataException("Formato o resolución no compatible.");
  if(Slices.Count<1||Slices.Count>256||Sequences.Count<1||Sequences.Count>128)throw new InvalidDataException("Límite: 256 slices y 128 secuencias.");
  var ids=new HashSet<string>();foreach(var slice in Slices){if(!ids.Add(slice!["id"]!.GetValue<string>()))throw new InvalidDataException("Slices duplicados.");var points=slice["points"]!.AsArray();if(points.Count<3||points.Count>1024)throw new InvalidDataException("Polígono inválido.");foreach(var p in points)if(!double.IsFinite(Number(p?["x"]))||!double.IsFinite(Number(p?["y"]))||Math.Abs(Number(p?["x"]))>=1e7||Math.Abs(Number(p?["y"]))>=1e7)throw new InvalidDataException("Coordenadas inválidas.");}
  ids.Clear();for(int s=0;s<Sequences.Count;s++){if(!ids.Add(Sequences[s]!["id"]!.GetValue<string>()))throw new InvalidDataException("Secuencias duplicadas.");if(Cells(s).Count!=Slices.Count||Count(s)<1||Count(s)>256||Cells(s).Any(r=>r!.AsArray().Count!=Count(s)))throw new InvalidDataException("Matriz inválida.");foreach(var row in Cells(s))foreach(var c in row!.AsArray())_=c!.GetValue<bool>();if(Sequences[s]?["durations"] is JsonArray weights&&(weights.Count!=Count(s)||weights.Any(w=>!new[]{.25,.5,1d,2d,4d}.Contains(Number(w)))))throw new InvalidDataException("Duraciones inválidas.");}
  if(!new[]{"Corte","Fade out","Pulso","Bézier"}.Contains(Envelope))throw new InvalidDataException("Envolvente inválida.");
  if(Envelope=="Bézier"){var nodes=Data["bezier"]?["nodes"]?.AsArray()??throw new InvalidDataException("Falta curva Bézier.");if(nodes.Count<2||nodes.Count>64)throw new InvalidDataException("Curva inválida.");double last=-1;foreach(var n in nodes){foreach(var key in new[]{"point","incoming","outgoing"})foreach(var axis in new[]{"x","y"}){double v=Number(n?[key]?[axis]);if(!double.IsFinite(v)||v<0||v>1)throw new InvalidDataException("Curva fuera de rango.");}double x=Number(n?["point"]?["x"]);if(x<=last)throw new InvalidDataException("Curva desordenada.");last=x;}if(Number(nodes[0]?["point"]?["x"])!=0||last!=1)throw new InvalidDataException("Extremos de curva inválidos.");}
 }
 public void Resize(int s,int count){count=Math.Clamp(count,1,256);foreach(var row in Cells(s)){var a=row!.AsArray();while(a.Count<count)a.Add(false);while(a.Count>count)a.RemoveAt(a.Count-1);}var weights=Sequences[s]!["durations"] as JsonArray??new JsonArray(Enumerable.Repeat(1d,Count(s)).Select(x=>JsonValue.Create(x)).ToArray());while(weights.Count<count)weights.Add(1d);while(weights.Count>count)weights.RemoveAt(weights.Count-1);if(weights.Parent==null)Sequences[s]!["durations"]=weights;}
 public void SetWeight(int s,int c,double weight){if(Sequences[s]!["durations"]==null)Sequences[s]!["durations"]=new JsonArray(Enumerable.Repeat(1d,Count(s)).Select(x=>JsonValue.Create(x)).ToArray());Sequences[s]!["durations"]![c]=weight;}
 public (int step,double phase) Position(int s,double beats){double total=Enumerable.Range(0,Count(s)).Sum(c=>Weight(s,c));double p=((beats*Division)%total+total)%total;for(int c=0;c<Count(s);c++){double w=Weight(s,c);if(p<w)return(c,p/w);p-=w;}return(0,0);}
 static double Cubic(double a,double b,double c,double d,double t){double u=1-t;return u*u*u*a+3*u*u*t*b+3*u*t*t*c+t*t*t*d;}
 public double Level(double phase){phase=Math.Clamp(phase,0,1);if(Envelope=="Fade out")return 1-phase;if(Envelope=="Pulso")return Math.Sin(phase*Math.PI);if(Envelope!="Bézier")return 1;var nodes=Data["bezier"]!["nodes"]!.AsArray();int i=0;while(i<nodes.Count-2&&phase>Number(nodes[i+1]?["point"]?["x"]))i++;var a=nodes[i]!;var b=nodes[i+1]!;double lo=0,hi=1;for(int j=0;j<28;j++){double t=(lo+hi)/2;if(Cubic(Number(a["point"]?["x"]),Number(a["outgoing"]?["x"]),Number(b["incoming"]?["x"]),Number(b["point"]?["x"]),t)<phase)lo=t;else hi=t;}return Math.Clamp(Cubic(Number(a["point"]?["y"]),Number(a["outgoing"]?["y"]),Number(b["incoming"]?["y"]),Number(b["point"]?["y"]),(lo+hi)/2),0,1);}
 public static Project ImportXml(string path){
  if(new FileInfo(path).Length>20_000_000)throw new InvalidDataException("XML mayor de 20 MB.");using var reader=XmlReader.Create(path,new XmlReaderSettings{DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=20_000_000});var xml=XDocument.Load(reader);var size=xml.Descendants("CurrentCompositionTextureSize").FirstOrDefault();double Read(XElement? e,string key,double fallback)=>e?.Attribute(key) is {} attr?double.Parse(attr.Value,CultureInfo.InvariantCulture):fallback;
  double width=Read(size,"width",1920),height=Read(size,"height",1080);var slices=new JsonArray();foreach(var e in xml.Descendants("Slice")){string name=e.Elements("Params").FirstOrDefault(x=>(string?)x.Attribute("name")=="Common")?.Elements("Param").FirstOrDefault(x=>(string?)x.Attribute("name")=="Name")?.Attribute("value")?.Value??$"Slice {slices.Count+1}";var points=new JsonArray();foreach(var v in e.Element("InputRect")?.Elements("v")??Enumerable.Empty<XElement>())points.Add(new JsonObject{["x"]=Read(v,"x",double.NaN),["y"]=Read(v,"y",double.NaN)});slices.Add(new JsonObject{["id"]=Guid.NewGuid().ToString(),["name"]=name,["points"]=points});}
  var cells=new JsonArray();for(int r=0;r<slices.Count;r++)cells.Add(new JsonArray(Enumerable.Range(0,16).Select(_=>JsonValue.Create(false)).ToArray()));return new(new JsonObject{["version"]=5,["width"]=width,["height"]=height,["bpm"]=120d,["division"]=2d,["envelope"]="Corte",["slices"]=slices,["sequences"]=new JsonArray(new JsonObject{["id"]=Guid.NewGuid().ToString(),["name"]="Chase 01",["cells"]=cells})});
 }
}
