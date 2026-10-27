// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
// ChaseLab local live bridge. Uses the official FreeFrameGL SDK (BSD-3-Clause).
#import <Foundation/Foundation.h>
#include <FFGLSDK.h>
#include <ffglex/FFGLScopedFBOBinding.h>
#include <atomic>
#include <thread>
#include <mutex>
#include <vector>
#include <cmath>
#include <algorithm>
#include <sys/stat.h>
#include <unistd.h>
#include <memory>
#include <string>
#include <cstring>

using namespace ffglex;
static double nowSeconds() { return NSDate.date.timeIntervalSince1970; }
static NSString* bridgeDirectory() {
    const char* overridePath=getenv("CHASELAB_BRIDGE_DIR");
    if(overridePath && overridePath[0]=='/') return [NSString stringWithUTF8String:overridePath];
    return [NSString stringWithFormat:@"/private/tmp/chaselab-%u",getuid()];
}
struct P { float x,y; };
static float cross(P a,P b,P c) { return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x); }
static bool inside(P p,P a,P b,P c) { const float e=0.00000001f; return cross(a,b,p)>=-e && cross(b,c,p)>=-e && cross(c,a,p)>=-e; }
static bool triangulate(std::vector<P> p,std::vector<P>& out) {
    if(p.size()<3) return false;
    if(std::abs(p.front().x-p.back().x)<1e-7 && std::abs(p.front().y-p.back().y)<1e-7) p.pop_back();
    if(p.size()<3) return false;
    double area=0; for(size_t i=0;i<p.size();++i) { P a=p[i], b=p[(i+1)%p.size()]; area+=a.x*b.y-a.y*b.x; }
    if(std::abs(area)<1e-9) return false;
    if(area<0) std::reverse(p.begin(),p.end());
    std::vector<P> result;
    while(p.size()>3) {
        bool found=false;
        for(size_t i=0;i<p.size();++i) {
            size_t a=(i+p.size()-1)%p.size(),c=(i+1)%p.size();
            if(cross(p[a],p[i],p[c])<=1e-9) continue;
            bool contains=false;
            for(size_t j=0;j<p.size();++j) if(j!=a && j!=i && j!=c && inside(p[j],p[a],p[i],p[c])) { contains=true;break; }
            if(contains) continue;
            result.insert(result.end(),{p[a],p[i],p[c]}); p.erase(p.begin()+i); found=true;break;
        }
        if(!found) return false;
    }
    result.insert(result.end(),p.begin(),p.end());out.insert(out.end(),result.begin(),result.end()); return true;
}
struct Vertex { P position; float minX,minY,maxX,maxY; };
struct Mesh { std::vector<Vertex> vertices; float intensity=0; double time=0; uint64_t sequence=0; std::string session;float phase=0;bool playing=false;int step=-1;std::string sequenceID; };
struct PlayerSequence { std::string id,name;int count=0;std::vector<uint8_t> bits;std::vector<double> durations;double total=0; };
struct PlayerEnvelope {std::string id,name;std::vector<float> values;};
struct PlayerCatalog {
    std::string session;double width=0,height=0;
    NSArray* polygons=nil;
    std::shared_ptr<std::vector<std::vector<Vertex>>> geometry;
    std::vector<PlayerSequence> sequences;std::vector<float> envelope;std::vector<PlayerEnvelope> envelopes;
};
static bool finiteNumber(id v,double &out) {if(![v isKindOfClass:NSNumber.class])return false;out=[v doubleValue];return std::isfinite(out);}
static std::shared_ptr<PlayerCatalog> parseCatalog(NSData* data,std::shared_ptr<PlayerCatalog> previous) {
    id root=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![root isKindOfClass:NSDictionary.class] || ![root[@"version"] isKindOfClass:NSNumber.class] || [root[@"version"] intValue]!=1)return {};
    auto result=std::make_shared<PlayerCatalog>();double w,h;
    id token=root[@"session"],polys=root[@"polygons"],sequences=root[@"sequences"],envelope=root[@"envelope"];
    if(![token isKindOfClass:NSString.class] || [token length]==0 || [token length]>128 || !finiteNumber(root[@"width"],w) || !finiteNumber(root[@"height"],h) || w<1 || h<1 || w>16384 || h>16384 || ![polys isKindOfClass:NSArray.class] || [polys count]<1 || [polys count]>256 || ![sequences isKindOfClass:NSArray.class] || [sequences count]<1 || [sequences count]>128 || ![envelope isKindOfClass:NSArray.class] || [envelope count]!=1025)return {};
    result->session=[token UTF8String];result->width=w;result->height=h;result->polygons=[polys copy];
    if(previous && [previous->polygons isEqualToArray:polys])result->geometry=previous->geometry;
    else {
        result->geometry=std::make_shared<std::vector<std::vector<Vertex>>>();size_t total=0;
        for(id polygon in polys) {
            if(![polygon isKindOfClass:NSArray.class] || [polygon count]<3 || [polygon count]>1024 || (total += [polygon count])>262144)return {};
            std::vector<P> points;
            for(id v in polygon) {double x,y;if(![v isKindOfClass:NSArray.class] || [v count]!=2 || !finiteNumber(v[0],x) || !finiteNumber(v[1],y) || std::abs(x)>10000 || std::abs(y)>10000)return {};points.push_back({(float)x,(float)y});}
            std::vector<P> triangles;if(!triangulate(points,triangles))return {};
            float minX=points[0].x,maxX=minX,minY=points[0].y,maxY=minY;
            for(P p:points){minX=std::min(minX,p.x);maxX=std::max(maxX,p.x);minY=std::min(minY,p.y);maxY=std::max(maxY,p.y);}
            std::vector<Vertex> vertices;for(P p:triangles)vertices.push_back({p,minX,minY,maxX,maxY});result->geometry->push_back(std::move(vertices));
        }
    }
    std::vector<std::string> ids;
    for(id seq in sequences) {
        double count;if(![seq isKindOfClass:NSDictionary.class] || ![seq[@"id"] isKindOfClass:NSString.class] || [seq[@"id"] length]<1 || [seq[@"id"] length]>128 || ![seq[@"name"] isKindOfClass:NSString.class] || [seq[@"name"] length]>4096 || !finiteNumber(seq[@"count"],count) || count<1 || count>256 || count!=floor(count) || ![seq[@"bits"] isKindOfClass:NSString.class] || [seq[@"bits"] length]>12000 || ![seq[@"durations"] isKindOfClass:NSArray.class] || [seq[@"durations"] count]!=(int)count)return {};
        PlayerSequence value;value.id=[seq[@"id"] UTF8String];value.name=[seq[@"name"] UTF8String];value.count=(int)count;
        if(std::find(ids.begin(),ids.end(),value.id)!=ids.end())return {};ids.push_back(value.id);
        NSData* bits=[[NSData alloc]initWithBase64EncodedString:seq[@"bits"] options:0];if(!bits || bits.length != value.count*(([polys count]+7)/8))return {};
        value.bits.assign((const uint8_t*)bits.bytes,(const uint8_t*)bits.bytes+bits.length);
        for(id d in seq[@"durations"]) {double weight;if(!finiteNumber(d,weight) || !(weight==0.25 || weight==0.5 || weight==1 || weight==2 || weight==4))return {};value.durations.push_back(weight);value.total+=weight;}
        result->sequences.push_back(std::move(value));
    }
    for(id n in envelope){double v;if(!finiteNumber(n,v) || v<0 || v>1)return {};result->envelope.push_back((float)v);}
    id library=root[@"envelopes"];
    if(library){
        if(![library isKindOfClass:NSArray.class] || [library count]>512)return {};
        std::vector<std::string> ids;
        for(id entry in library){
            if(![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isKindOfClass:NSString.class] || [entry[@"id"] length]<1 || [entry[@"id"] length]>128 || ![entry[@"name"] isKindOfClass:NSString.class] || [entry[@"name"] length]<1 || [entry[@"name"] length]>128 || ![entry[@"values"] isKindOfClass:NSArray.class] || [entry[@"values"] count]!=1025)return {};
            PlayerEnvelope e;e.id=[entry[@"id"] UTF8String];e.name=[entry[@"name"] UTF8String];
            if(std::find(ids.begin(),ids.end(),e.id)!=ids.end())return {};ids.push_back(e.id);
            for(id value in entry[@"values"]){double v;if(!finiteNumber(value,v) || v<0 || v>1)return {};e.values.push_back((float)v);}
            result->envelopes.push_back(std::move(e));
        }
    }
    return result;
}
struct OutlineBatch {int first,count,fillFirst,fillCount,edgeStart,edgeCount;float centerX,centerY,random,width;};
class Outliner:public CFFGLPlugin {
    float values[24]={0,0,10,1,0,0,1,1,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,1};
    FFGLShader strokeShader,fillShader,compositeShader;FFGLScreenQuad quad;FFGLFBO strokeMask,fillMask;
    GLuint vao=0,vbo=0,edgesBuffer=0,edgesTexture=0,curveTexture=0;
    std::vector<OutlineBatch>batches;std::vector<float>uploadedCurve;
    std::shared_ptr<PlayerCatalog>catalog,pending,geometryCache;std::mutex mutex;std::thread reader;std::atomic<bool>running{false};
    std::atomic<double>latestFrame{0},lastRender{0};std::atomic<int>inputW{0},inputH{0},mountW{0},mountH{0};
    std::atomic<float>bpm{0},barPhase{0};std::atomic<double>beatTime{0};std::atomic<uint64_t>gpuUploads{0};
    int cacheW=0,cacheH=0;bool geometryDirty=true,fillDirty=true;std::string envelopeID,display;NSString* instanceID=NSUUID.UUID.UUIDString;
    void runReader();void updateCatalog();void rebuild(int w,int h);void visibility();
public:
    Outliner(){
        SetMinInputs(SOURCE_MODE?0:1);SetMaxInputs(SOURCE_MODE?0:1);
        SetOptionParamInfo(0,"View",1,0);SetParamElementInfo(0,0,"All",0);
        SetOptionParamInfo(1,"Mode",2,0);SetParamElementInfo(1,0,"Pixel",0);SetParamElementInfo(1,1,"Filled",1);
        SetParamInfof(2,"Width",FF_TYPE_INTEGER);SetParamRange(2,0,50);SetParamInfof(3,"Fill",FF_TYPE_STANDARD);
        SetParamInfof(4,"Color",FF_TYPE_HUE);SetParamInfof(5,"sat",FF_TYPE_SATURATION);SetParamInfof(6,"brt",FF_TYPE_BRIGHTNESS);SetParamInfof(7,"alpha",FF_TYPE_ALPHA);
        SetParamInfof(8,"Feather",FF_TYPE_STANDARD);SetParamInfof(9,"Animate",FF_TYPE_BOOLEAN);SetParamInfof(10,"Phase",FF_TYPE_STANDARD);SetParamInfof(11,"Fan",FF_TYPE_STANDARD);SetParamInfof(12,"Randomise",FF_TYPE_STANDARD);SetParamInfof(13,"Length",FF_TYPE_STANDARD);
        SetParamInfof(14,"Count",FF_TYPE_INTEGER);SetParamRange(14,1,10);SetParamInfof(15,"Odd/Even",FF_TYPE_BOOLEAN);SetParamInfof(16,"Flip Direction",FF_TYPE_BOOLEAN);
        SetOptionParamInfo(17,"Envelope",1,0);SetParamElementInfo(17,0,"Proyecto",0);
        SetParamInfof(18,"Background Color",FF_TYPE_HUE);SetParamInfof(19,"Background sat",FF_TYPE_SATURATION);SetParamInfof(20,"Background brt",FF_TYPE_BRIGHTNESS);SetParamInfof(21,"Background alpha",FF_TYPE_ALPHA);
        SetParamInfof(22,"Show Original",FF_TYPE_BOOLEAN);SetParamInfof(23,"Amount",FF_TYPE_STANDARD);visibility();
    }
    ~Outliner()override{running=false;if(reader.joinable())reader.join();}
    FFResult SetFloatParameter(unsigned i,float v)override{
        if(i>=24||!std::isfinite(v))return FF_FAIL;
        if(i==0)v=0;else if(i==1)v=std::round(std::clamp(v,0.f,1.f));else if(i==2)v=std::round(std::clamp(v,0.f,50.f));else if(i==14)v=std::round(std::clamp(v,1.f,10.f));else if(i==17){v=std::round(std::clamp(v,0.f,catalog?(float)catalog->envelopes.size():512.f));envelopeID=catalog&&v>0?catalog->envelopes[(int)v-1].id:"";}else v=std::clamp(v,0.f,1.f);
        if(values[i]!=v){values[i]=v;if(i==1||i==2||i==3)geometryDirty=true;if(i==1||i==9)visibility();}return FF_SUCCESS;
    }
    float GetFloatParameter(unsigned i)override{return i<24?values[i]:0;}
    void SetBeatInfo(float tempo,float phase)override{if(std::isfinite(tempo)&&tempo>=20&&tempo<=300&&std::isfinite(phase)){bpm=tempo;barPhase=phase-floor(phase);beatTime=nowSeconds();}}
    FFResult InitGL(const FFGLViewportStruct*)override;FFResult DeInitGL()override;FFResult ProcessOpenGL(ProcessOpenGLStruct*)override;
};
#if SOURCE_MODE
static CFFGLPluginInfo info(PluginFactory<Outliner>,"COS1","CL Outline Src",2,1,0,1,FF_SOURCE,"Slice outline source","ChaseLab Outliner 0.1.1");
#else
static CFFGLPluginInfo info(PluginFactory<Outliner>,"COL1","CL Outliner",2,1,0,1,FF_EFFECT,"Slice outline effect","ChaseLab Outliner 0.1.1");
#endif
void Outliner::visibility(){SetParamVisibility(2,values[1]==0,true);SetParamVisibility(3,values[1]==1,true);SetParamVisibility(8,values[9]<.5f,true);for(int i=10;i<=17;++i)SetParamVisibility(i,values[9]>=.5f,true);SetParamVisibility(22,!SOURCE_MODE,true);}
void Outliner::updateCatalog(){
    std::shared_ptr<PlayerCatalog>incoming;{std::unique_lock<std::mutex>lock(mutex,std::try_to_lock);if(lock.owns_lock())incoming=pending;}
    if(!incoming||incoming==catalog)return;
    if(!catalog||incoming->geometry!=catalog->geometry)geometryDirty=true;catalog=incoming;
    if(!envelopeID.empty()){auto it=std::find_if(catalog->envelopes.begin(),catalog->envelopes.end(),[&](const auto&e){return e.id==envelopeID;});values[17]=it==catalog->envelopes.end()?0:(float)(it-catalog->envelopes.begin())+1;}
    values[17]=std::clamp(values[17],0.f,(float)catalog->envelopes.size());envelopeID=values[17]>0?catalog->envelopes[(int)values[17]-1].id:"";
    std::vector<std::string>names{"Proyecto"};std::vector<float>v{0};for(size_t i=0;i<catalog->envelopes.size();++i){names.push_back(catalog->envelopes[i].name);v.push_back((float)i+1);}SetParamElements(17,std::move(names),v,true);RaiseParamEvent(17,FF_EVENT_FLAG_VALUE);
}
void Outliner::runReader(){
    ino_t catalogInode=0,frameInode=0;timespec cm{},fm{};double ackTime=0;std::shared_ptr<PlayerCatalog>previous;
    while(running){@autoreleasepool{
        NSString*dir=bridgeDirectory();struct stat st;
        if(lstat(dir.fileSystemRepresentation,&st)==0&&S_ISDIR(st.st_mode)&&st.st_uid==getuid()&&!(st.st_mode&0077)){
            NSString*path=[dir stringByAppendingPathComponent:@"catalog.json"];
            if(lstat(path.fileSystemRepresentation,&st)==0&&S_ISREG(st.st_mode)&&st.st_uid==getuid()&&st.st_size>0&&st.st_size<32*1024*1024&&(st.st_ino!=catalogInode||st.st_mtimespec.tv_sec!=cm.tv_sec||st.st_mtimespec.tv_nsec!=cm.tv_nsec)){
                catalogInode=st.st_ino;cm=st.st_mtimespec;auto parsed=parseCatalog([NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:nil],previous);if(parsed){if(previous&&previous->session!=parsed->session)latestFrame=0;previous=parsed;std::lock_guard<std::mutex>lock(mutex);pending=parsed;}
            }
            path=[dir stringByAppendingPathComponent:@"frame.json"];
            if(lstat(path.fileSystemRepresentation,&st)==0&&S_ISREG(st.st_mode)&&st.st_uid==getuid()&&st.st_size>0&&st.st_size<4*1024*1024&&(st.st_ino!=frameInode||st.st_mtimespec.tv_sec!=fm.tv_sec||st.st_mtimespec.tv_nsec!=fm.tv_nsec)){
                frameInode=st.st_ino;fm=st.st_mtimespec;NSData*bytes=[NSData dataWithContentsOfFile:path];id d=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;double t;
                if([d isKindOfClass:NSDictionary.class]&&[d[@"version"] isKindOfClass:NSNumber.class]&&[d[@"version"] intValue]==1&&[d[@"enabled"] isKindOfClass:NSNumber.class]&&finiteNumber(d[@"time"],t)&&[d[@"session"] isKindOfClass:NSString.class]&&[d[@"session"] length]>0&&[d[@"session"] length]<=128){std::lock_guard<std::mutex>lock(mutex);latestFrame=previous&&previous->session==[d[@"session"] UTF8String]&&[d[@"enabled"] boolValue]?t:0;}else latestFrame=0;
            }
            double now=nowSeconds(),render=lastRender.load();
            if(now-ackTime>.25&&now-render<.5){NSDictionary*d=@{@"time":@(render),@"sequence":@1,@"effect":@"outliner",@"source":@(SOURCE_MODE),@"bpm":@(bpm.load()),@"barPhase":@(barPhase.load()),@"beatTime":@(beatTime.load()),@"inputWidth":@(inputW.load()),@"inputHeight":@(inputH.load()),@"mountWidth":@(mountW.load()),@"mountHeight":@(mountH.load()),@"gpuUploads":@(gpuUploads.load()),@"resolutionMismatch":@(inputW.load()!=mountW.load()||inputH.load()!=mountH.load())};NSData*b=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];[b writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"outliner-%@.json",instanceID]] options:NSDataWritingAtomic error:nil];[b writeToFile:[dir stringByAppendingPathComponent:@"receiver.json"] options:NSDataWritingAtomic error:nil];ackTime=now;}
        }
    }std::this_thread::sleep_for(std::chrono::milliseconds(10));}
}
static const char* vertexShader=R"(#version 410 core
layout(location=0)in vec2 position;void main(){gl_Position=vec4(position,0,1);}
)";
static const char* fillFragment=R"(#version 410 core
out vec4 color;void main(){color=vec4(1);}
)";
static const char* strokeFragment=R"(#version 410 core
uniform samplerBuffer Edges;uniform sampler2D Curve;uniform vec2 OutputSize;uniform int EdgeStart;uniform int EdgeCount;
uniform int Filled;uniform float Width;uniform float Feather;uniform int Animate;uniform float Phase;uniform float Fan;uniform float Randomise;uniform float Length;uniform int Count;uniform int Flip;uniform int Odd;uniform int SliceIndex;uniform vec2 Center;uniform float Seed;
out vec4 color;
float animatedLevel(float pos){
 float direction=Center.x>0?-1:1;
 if(abs(Center.x)<.00001)pos=abs(fract(pos)-.5)*2;
 if(Flip!=0)direction=-direction;if(Odd!=0&&SliceIndex%2!=0)direction=-direction;
 float phase=Phase+Fan*clamp(length(Center)*.70710678,0,1)+Randomise*Seed;
 float x=fract((direction*pos-phase)*float(Count));
 return x>=Length?0:texture(Curve,vec2((x/Length*1024+.5)/1025,.5)).r;
}
void main(){
 vec2 p=gl_FragCoord.xy;bool inside=false;float nearest=1e30,arc=0,total=0;
 for(int i=0;i<EdgeCount;i++){
  vec4 e=texelFetch(Edges,EdgeStart+i);vec2 a=(e.xy*.5+.5)*OutputSize,b=(e.zw*.5+.5)*OutputSize,d=b-a;float len=length(d);if(len<.00001)continue;
  float t=clamp(dot(p-a,d)/dot(d,d),0,1),dist=length(p-a-d*t);if(dist<nearest){nearest=dist;arc=total+t*len;}total+=len;
  if((a.y>p.y)!=(b.y>p.y)){float x=a.x+(p.y-a.y)*(b.x-a.x)/(b.y-a.y);if(p.x<x)inside=!inside;}
 }
 if(!inside||Width<=0)discard;
 float coverage=1-smoothstep(Width-.5,Width+.5,nearest);
 if(Animate==0&&Feather>0)coverage*=1-smoothstep(Width*(1-Feather),Width,nearest);
 if(Animate!=0){
  if(Length<=0)discard;
  float level=animatedLevel(arc/max(total,.00001));
  if(Filled!=0){
   // Blend intensities, not wrapped arc coordinates: a hard nearest-edge switch
   // creates triangular wedges in broad strokes. Keep the pixel-stroke path intact.
   float weighted=0,weightSum=0,offset=0,radius=max(1.0,Width*.25);
   for(int i=0;i<EdgeCount;i++){
    vec4 e=texelFetch(Edges,EdgeStart+i);vec2 a=(e.xy*.5+.5)*OutputSize,b=(e.zw*.5+.5)*OutputSize,d=b-a;float len=length(d);if(len<.00001)continue;
    float t=clamp(dot(p-a,d)/dot(d,d),0,1),dist=length(p-a-d*t);
    float weight=exp(-(dist-nearest)/radius);
    weighted+=weight*animatedLevel((offset+t*len)/max(total,.00001));weightSum+=weight;offset+=len;
   }
   level=weighted/max(weightSum,.00001);
  }
  coverage*=level;
 }
 color=vec4(coverage);
}
)";
static const char* compositeVertex=R"(#version 410 core
layout(location=0)in vec4 vPosition;layout(location=1)in vec2 vUV;out vec2 uv;void main(){gl_Position=vPosition;uv=vUV;}
)";
static const char* compositeFragment=R"(#version 410 core
in vec2 uv;out vec4 color;uniform sampler2D Stroke;uniform sampler2D FillMask;uniform sampler2D InputTexture;uniform vec2 MaxUV;uniform vec4 StrokeColor;uniform vec4 BackgroundColor;uniform int ShowOriginal;uniform int IsSource;uniform int Live;uniform float Amount;
vec3 hsv(vec3 c){vec3 p=abs(fract(c.xxx+vec3(0,2.0/3,1.0/3))*6-3);return c.z*mix(vec3(1),clamp(p-1,0,1),c.y);}
void main(){vec4 dry=IsSource==0?texture(InputTexture,uv*MaxUV):vec4(0);if(Live==0){color=dry;return;}
 float a=texture(Stroke,uv).r*StrokeColor.a;vec4 stroke=vec4(hsv(StrokeColor.rgb)*a,a);float ba=BackgroundColor.a>0?texture(FillMask,uv).r*BackgroundColor.a:0;vec4 bg=vec4(hsv(BackgroundColor.rgb)*ba,ba);vec4 overlay=stroke+bg*(1-stroke.a);vec4 base=ShowOriginal!=0?dry:vec4(0);vec4 result=overlay+base*(1-overlay.a);color=mix(dry,result,Amount);}
)";
void Outliner::rebuild(int w,int h){
 std::vector<P>verts;std::vector<float>edges;batches.clear();int row=0;
 for(id polygon in catalog->polygons){
  std::vector<P>points;for(id v in polygon){P p{[v[0] floatValue],[v[1] floatValue]};if(points.empty()||std::hypot(points.back().x-p.x,points.back().y-p.y)>1e-7)points.push_back(p);}
  if(points.size()>1&&std::hypot(points.front().x-points.back().x,points.front().y-points.back().y)<1e-7)points.pop_back();
  double area=0;float minX=points[0].x,maxX=minX,minY=points[0].y,maxY=minY;uint32_t seed=2166136261u;
  for(size_t i=0;i<points.size();++i){P a=points[i],b=points[(i+1)%points.size()];area+=a.x*b.y-a.y*b.x;minX=std::min(minX,a.x);maxX=std::max(maxX,a.x);minY=std::min(minY,a.y);maxY=std::max(maxY,a.y);uint32_t x,y;std::memcpy(&x,&a.x,4);std::memcpy(&y,&a.y,4);seed=(seed^x)*16777619u;seed=(seed^y)*16777619u;}
  if(area<0)std::reverse(points.begin(),points.end());
  OutlineBatch batch{};batch.fillFirst=(int)verts.size();for(const auto&v:(*catalog->geometry)[row])verts.push_back(v.position);batch.fillCount=(int)verts.size()-batch.fillFirst;
  batch.centerX=(minX+maxX)/2;batch.centerY=(minY+maxY)/2;batch.random=(seed&65535)/65535.f;
  batch.width=values[1]<.5f?values[2]:values[3]*std::min((maxX-minX)*w,(maxY-minY)*h)/4;
  batch.edgeStart=(int)edges.size()/4;batch.edgeCount=(int)points.size();batch.first=(int)verts.size();
  for(size_t i=0;i<points.size();++i){P a=points[i],b=points[(i+1)%points.size()];edges.insert(edges.end(),{a.x,a.y,b.x,b.y});
   const float dx=(b.x-a.x)*w/2,dy=(b.y-a.y)*h/2,len=std::hypot(dx,dy);if(len<1e-6)continue;float r=batch.width+1;
   P along{dx/len*r*2/w,dy/len*r*2/h},normal{-dy/len*r*2/w,dx/len*r*2/h};
   P q0{a.x-along.x+normal.x,a.y-along.y+normal.y},q1{b.x+along.x+normal.x,b.y+along.y+normal.y},q2{b.x+along.x-normal.x,b.y+along.y-normal.y},q3{a.x-along.x-normal.x,a.y-along.y-normal.y};verts.insert(verts.end(),{q0,q1,q2,q0,q2,q3});
  }
  batch.count=(int)verts.size()-batch.first;batches.push_back(batch);++row;
 }
 glBindBuffer(GL_ARRAY_BUFFER,vbo);glBufferData(GL_ARRAY_BUFFER,verts.size()*sizeof(P),verts.data(),GL_DYNAMIC_DRAW);glBindBuffer(GL_ARRAY_BUFFER,0);
 glBindBuffer(GL_TEXTURE_BUFFER,edgesBuffer);glBufferData(GL_TEXTURE_BUFFER,edges.size()*sizeof(float),edges.data(),GL_DYNAMIC_DRAW);glBindBuffer(GL_TEXTURE_BUFFER,0);
 {ScopedSamplerActivation unit(2);GLint previous;glGetIntegerv(GL_TEXTURE_BINDING_BUFFER,&previous);glBindTexture(GL_TEXTURE_BUFFER,edgesTexture);glTexBuffer(GL_TEXTURE_BUFFER,GL_RGBA32F,edgesBuffer);glBindTexture(GL_TEXTURE_BUFFER,previous);}
 cacheW=w;cacheH=h;geometryDirty=false;fillDirty=true;geometryCache=catalog;++gpuUploads;
}
FFResult Outliner::InitGL(const FFGLViewportStruct*vp){
 if(!strokeShader.Compile(vertexShader,strokeFragment)||!fillShader.Compile(vertexShader,fillFragment)||!compositeShader.Compile(compositeVertex,compositeFragment)||!quad.Initialise()){DeInitGL();return FF_FAIL;}
 glGenVertexArrays(1,&vao);glGenBuffers(1,&vbo);glBindVertexArray(vao);glBindBuffer(GL_ARRAY_BUFFER,vbo);glEnableVertexAttribArray(0);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,sizeof(P),nullptr);glBindBuffer(GL_ARRAY_BUFFER,0);glBindVertexArray(0);
 glGenBuffers(1,&edgesBuffer);glGenTextures(1,&edgesTexture);glGenTextures(1,&curveTexture);running=true;
 try{reader=std::thread(&Outliner::runReader,this);}catch(...){running=false;DeInitGL();return FF_FAIL;}return CFFGLPlugin::InitGL(vp);
}
FFResult Outliner::DeInitGL(){
 running=false;if(reader.joinable())reader.join();strokeMask.Release();fillMask.Release();quad.Release();strokeShader.FreeGLResources();fillShader.FreeGLResources();compositeShader.FreeGLResources();
 if(vao)glDeleteVertexArrays(1,&vao);if(vbo)glDeleteBuffers(1,&vbo);if(edgesBuffer)glDeleteBuffers(1,&edgesBuffer);if(edgesTexture)glDeleteTextures(1,&edgesTexture);if(curveTexture)glDeleteTextures(1,&curveTexture);vao=vbo=edgesBuffer=edgesTexture=curveTexture=0;uploadedCurve.clear();batches.clear();geometryCache.reset();geometryDirty=true;fillDirty=true;cacheW=cacheH=0;
 [[NSFileManager defaultManager]removeItemAtPath:[bridgeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"outliner-%@.json",instanceID]] error:nil];return FF_SUCCESS;
}
FFResult Outliner::ProcessOpenGL(ProcessOpenGLStruct*p){
 if(!p||(!SOURCE_MODE&&(p->numInputTextures<1||!p->inputTextures||!p->inputTextures[0])))return FF_FAIL;
 updateCatalog();bool live=catalog&&std::abs(nowSeconds()-latestFrame.load())<1;
 GLint vp[4];glGetIntegerv(GL_VIEWPORT,vp);int w=vp[2],h=vp[3];if(w<=0||h<=0||w>16384||h>16384)return FF_FAIL;
 inputW=SOURCE_MODE?w:p->inputTextures[0]->Width;inputH=SOURCE_MODE?h:p->inputTextures[0]->Height;mountW=catalog?(int)catalog->width:0;mountH=catalog?(int)catalog->height:0;
 if(strokeMask.GetWidth()!=w||strokeMask.GetHeight()!=h){strokeMask.Release();fillMask.Release();if(!strokeMask.Initialise(w,h)||!fillMask.Initialise(w,h))return FF_FAIL;geometryDirty=true;}
 const GLenum capabilities[]={GL_CULL_FACE,GL_DEPTH_TEST,GL_SCISSOR_TEST,GL_STENCIL_TEST};GLboolean savedCaps[4],writeMask[4];for(int i=0;i<4;++i){savedCaps[i]=glIsEnabled(capabilities[i]);glDisable(capabilities[i]);}glGetBooleanv(GL_COLOR_WRITEMASK,writeMask);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);GLint savedVAO,savedArray,savedTexBuffer;glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&savedVAO);glGetIntegerv(GL_ARRAY_BUFFER_BINDING,&savedArray);glGetIntegerv(GL_TEXTURE_BUFFER,&savedTexBuffer);
 GLboolean blending=glIsEnabled(GL_BLEND);GLint eqRGB,eqA;glGetIntegerv(GL_BLEND_EQUATION_RGB,&eqRGB);glGetIntegerv(GL_BLEND_EQUATION_ALPHA,&eqA);GLfloat clear[4];glGetFloatv(GL_COLOR_CLEAR_VALUE,clear);glDisable(GL_BLEND);
 if(live){
  if(geometryDirty||cacheW!=w||cacheH!=h)rebuild(w,h);
  const auto&curve=values[17]>0?catalog->envelopes[(int)values[17]-1].values:catalog->envelope;
  if(curve!=uploadedCurve){ScopedSamplerActivation unit(3);Scoped2DTextureBinding texture(curveTexture);glTexImage2D(GL_TEXTURE_2D,0,GL_R32F,1025,1,0,GL_RED,GL_FLOAT,curve.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);uploadedCurve=curve;}
  if(fillDirty&&values[21]>0){ScopedFBOBinding target(fillMask.GetGLID(),ScopedFBOBinding::RB_REVERT);glViewport(0,0,w,h);glClearColor(0,0,0,0);glClear(GL_COLOR_BUFFER_BIT);ScopedShaderBinding shader(fillShader.GetGLID());glEnable(GL_BLEND);glBlendEquation(GL_MAX);glBindVertexArray(vao);for(const auto&b:batches)glDrawArrays(GL_TRIANGLES,b.fillFirst,b.fillCount);glBindVertexArray(0);glDisable(GL_BLEND);fillDirty=false;}
 }
 {
  ScopedFBOBinding target(strokeMask.GetGLID(),ScopedFBOBinding::RB_REVERT);glViewport(0,0,w,h);glClearColor(0,0,0,0);glClear(GL_COLOR_BUFFER_BIT);
  if(live){ScopedShaderBinding shader(strokeShader.GetGLID());ScopedSamplerActivation edgeUnit(2);GLint previous;glGetIntegerv(GL_TEXTURE_BINDING_BUFFER,&previous);glBindTexture(GL_TEXTURE_BUFFER,edgesTexture);
   ScopedSamplerActivation curveUnit(3);Scoped2DTextureBinding curve(curveTexture);strokeShader.Set("Edges",2);strokeShader.Set("Curve",3);strokeShader.Set("OutputSize",(float)w,(float)h);
   glUniform1i(strokeShader.FindUniform("Filled"),values[1]>.5);glUniform1i(strokeShader.FindUniform("Animate"),values[9]>.5);glUniform1f(strokeShader.FindUniform("Feather"),values[8]);glUniform1f(strokeShader.FindUniform("Phase"),values[10]);glUniform1f(strokeShader.FindUniform("Fan"),values[11]);glUniform1f(strokeShader.FindUniform("Randomise"),values[12]);glUniform1f(strokeShader.FindUniform("Length"),values[13]);glUniform1i(strokeShader.FindUniform("Count"),(int)values[14]);glUniform1i(strokeShader.FindUniform("Odd"),values[15]>.5);glUniform1i(strokeShader.FindUniform("Flip"),values[16]>.5);
   glEnable(GL_BLEND);glBlendEquation(GL_MAX);glBindVertexArray(vao);
   for(size_t i=0;i<batches.size();++i){const auto&b=batches[i];glUniform1i(strokeShader.FindUniform("EdgeStart"),b.edgeStart);glUniform1i(strokeShader.FindUniform("EdgeCount"),b.edgeCount);glUniform1i(strokeShader.FindUniform("SliceIndex"),(int)i);glUniform1f(strokeShader.FindUniform("Width"),b.width);glUniform1f(strokeShader.FindUniform("Seed"),b.random);strokeShader.Set("Center",b.centerX,b.centerY);glDrawArrays(GL_TRIANGLES,b.first,b.count);}
   glBindVertexArray(0);glDisable(GL_BLEND);{ScopedSamplerActivation restore(2);glBindTexture(GL_TEXTURE_BUFFER,previous);}
  }
 }
 glClearColor(clear[0],clear[1],clear[2],clear[3]);glBlendEquationSeparate(eqRGB,eqA);glViewport(vp[0],vp[1],vp[2],vp[3]);
 {
  ScopedShaderBinding shader(compositeShader.GetGLID());ScopedSamplerActivation u0(0);Scoped2DTextureBinding input(SOURCE_MODE?strokeMask.GetTextureInfo().Handle:p->inputTextures[0]->Handle);ScopedSamplerActivation u1(1);Scoped2DTextureBinding stroke(strokeMask.GetTextureInfo().Handle);ScopedSamplerActivation u2(2);Scoped2DTextureBinding fill(fillMask.GetTextureInfo().Handle);
  compositeShader.Set("InputTexture",0);compositeShader.Set("Stroke",1);compositeShader.Set("FillMask",2);FFGLTexCoords uv{1,1};if(!SOURCE_MODE)uv=GetMaxGLTexCoords(*p->inputTextures[0]);compositeShader.Set("MaxUV",uv.s,uv.t);
  glUniform4f(compositeShader.FindUniform("StrokeColor"),values[4],values[5],values[6],values[7]);glUniform4f(compositeShader.FindUniform("BackgroundColor"),values[18],values[19],values[20],values[21]);glUniform1i(compositeShader.FindUniform("ShowOriginal"),values[22]>.5);glUniform1i(compositeShader.FindUniform("IsSource"),SOURCE_MODE);glUniform1i(compositeShader.FindUniform("Live"),live);glUniform1f(compositeShader.FindUniform("Amount"),values[23]);quad.Draw();
 }
 if(blending)glEnable(GL_BLEND);for(int i=0;i<4;++i)if(savedCaps[i])glEnable(capabilities[i]);glColorMask(writeMask[0],writeMask[1],writeMask[2],writeMask[3]);glBindVertexArray(savedVAO);glBindBuffer(GL_ARRAY_BUFFER,savedArray);glBindBuffer(GL_TEXTURE_BUFFER,savedTexBuffer);if(live)lastRender=nowSeconds();return FF_SUCCESS;
}
