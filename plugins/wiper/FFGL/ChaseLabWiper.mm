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
struct WiperBatch {int first,count;float axisX,axisY,minProjection,maxProjection,centerX;};
class Wiper:public CFFGLPlugin {
 float values[14]={0,0,0,0,.25,0,0,1,0,1,0,0,0,1};
 FFGLShader geometryShader,compositeShader;FFGLScreenQuad quad;FFGLFBO mask;GLuint vao=0,vbo=0,curveTexture=0;
 std::vector<WiperBatch>batches;std::vector<float>uploadedCurve;
 std::shared_ptr<PlayerCatalog>catalog,pending,geometryCache;std::mutex mutex,triggerMutex;std::thread reader;std::atomic<bool>running{false};
 std::atomic<double>latestFrame{0},lastRender{0};std::atomic<int>inputW{0},inputH{0},mountW{0},mountH{0},activeStep{-1},modeAck{0};
 std::atomic<float>bpm{0},barPhase{0};std::atomic<double>beatTime{0};std::atomic<uint64_t>gpuUploads{0};
 int cacheW=0,cacheH=0,cursor=-1,pendingNext=0;bool geometryDirty=true,held=false;double triggerTime=-1;
 std::string selectedID,envelopeID,display;NSString*instanceID=NSUUID.UUID.UUIDString;
 void runReader();void updateCatalog();void rebuild(int,int);void visibility();
public:
 Wiper(){SetMinInputs(1);SetMaxInputs(1);
  SetOptionParamInfo(0,"Scaling",2,0);SetParamElementInfo(0,0,"Mask",0);SetParamElementInfo(0,1,"Fill",1);
  SetOptionParamInfo(1,"Sequence",1,0);SetParamElementInfo(1,0,"Sin proyecto",0);
  SetOptionParamInfo(2,"Mode",2,0);SetParamElementInfo(2,0,"Auto",0);SetParamElementInfo(2,1,"Manual",1);
  SetParamInfof(3,"Next",FF_TYPE_EVENT);SetParamInfof(4,"Speed",FF_TYPE_STANDARD);
  SetOptionParamInfo(5,"Envelope",1,0);SetParamElementInfo(5,0,"Proyecto",0);
  SetParamInfof(6,"Step",FF_TYPE_STANDARD);SetParamInfof(7,"Length",FF_TYPE_STANDARD);SetParamInfof(8,"Overlap",FF_TYPE_STANDARD);
  SetParamInfof(9,"Loops",FF_TYPE_INTEGER);SetParamRange(9,1,4);
  SetParamInfof(10,"Flip Direction",FF_TYPE_BOOLEAN);SetParamInfof(11,"Odd/Even",FF_TYPE_BOOLEAN);SetParamInfof(12,"Swap Directions",FF_TYPE_BOOLEAN);SetParamInfof(13,"Amount",FF_TYPE_STANDARD);visibility();
 }
 ~Wiper()override{running=false;if(reader.joinable())reader.join();}
 FFResult SetFloatParameter(unsigned i,float v)override{
  if(i>=14||!std::isfinite(v))return FF_FAIL;
  if(i==3){std::lock_guard<std::mutex>lock(triggerMutex);if(v>.5&&!held)pendingNext=std::min(256,pendingNext+1);held=v>.5;return FF_SUCCESS;}
  if(i==0||i==2)v=std::round(std::clamp(v,0.f,1.f));else if(i==1)v=std::round(std::clamp(v,0.f,catalog?(float)catalog->sequences.size()-1:127.f));else if(i==5)v=std::round(std::clamp(v,0.f,catalog?(float)catalog->envelopes.size():512.f));else if(i==9)v=std::round(std::clamp(v,1.f,4.f));else v=std::clamp(v,0.f,1.f);
  if(i==1){selectedID=catalog?catalog->sequences[(int)v].id:"";if(values[i]!=v){cursor=-1;triggerTime=-1;}}
  if(i==5)envelopeID=catalog&&v>0?catalog->envelopes[(int)v-1].id:"";
  if(i==2&&values[i]!=v){cursor=-1;triggerTime=-1;{std::lock_guard<std::mutex>lock(triggerMutex);pendingNext=0;held=false;}}
  if(i==12&&values[i]!=v)geometryDirty=true;
  values[i]=v;if(i==2)visibility();return FF_SUCCESS;
 }
 float GetFloatParameter(unsigned i)override{return i==3?0:i<14?values[i]:0;}
 char*GetParameterDisplay(unsigned i)override{if(i==6){display="Step "+std::to_string(std::max(0,activeStep.load())+1);return display.data();}if(i==4){display=std::to_string(4*pow(1./32,values[4])).substr(0,4)+" s";return display.data();}return CFFGLPlugin::GetParameterDisplay(i);}
 void SetBeatInfo(float tempo,float phase)override{if(std::isfinite(tempo)&&tempo>=20&&tempo<=300&&std::isfinite(phase)){bpm=tempo;barPhase=phase-floor(phase);beatTime=nowSeconds();}}
 FFResult InitGL(const FFGLViewportStruct*)override;FFResult DeInitGL()override;FFResult ProcessOpenGL(ProcessOpenGLStruct*)override;
};
static CFFGLPluginInfo info(PluginFactory<Wiper>,"CWI1","CL Wiper",2,1,0,1,FF_EFFECT,"Gradient wipes over slice sequences","ChaseLab Wiper 0.1");
void Wiper::visibility(){bool manual=values[2]>.5;SetParamVisibility(3,manual,true);SetParamVisibility(4,manual,true);SetParamVisibility(6,!manual,true);SetParamVisibility(8,!manual,true);SetParamVisibility(9,!manual,true);}
void Wiper::updateCatalog(){
 std::shared_ptr<PlayerCatalog>incoming;{std::unique_lock<std::mutex>lock(mutex,std::try_to_lock);if(lock.owns_lock())incoming=pending;}if(!incoming||incoming==catalog)return;
 std::string oldID=selectedID;bool reset=!catalog||incoming->session!=catalog->session;int oldCount=catalog?catalog->sequences[(int)values[1]].count:0;
 if(!catalog||incoming->geometry!=catalog->geometry)geometryDirty=true;catalog=incoming;
 if(!selectedID.empty()){auto it=std::find_if(catalog->sequences.begin(),catalog->sequences.end(),[&](const auto&s){return s.id==selectedID;});values[1]=it==catalog->sequences.end()?0:(float)(it-catalog->sequences.begin());}
 values[1]=std::clamp(values[1],0.f,(float)catalog->sequences.size()-1);selectedID=catalog->sequences[(int)values[1]].id;
 if(reset||oldID!=selectedID||oldCount!=catalog->sequences[(int)values[1]].count){cursor=-1;triggerTime=-1;}
 std::vector<std::string>names;std::vector<float>v;for(size_t i=0;i<catalog->sequences.size();++i){names.push_back(catalog->sequences[i].name);v.push_back((float)i);}SetParamElements(1,std::move(names),v,true);RaiseParamEvent(1,FF_EVENT_FLAG_VALUE);
 if(!envelopeID.empty()){auto it=std::find_if(catalog->envelopes.begin(),catalog->envelopes.end(),[&](const auto&e){return e.id==envelopeID;});values[5]=it==catalog->envelopes.end()?0:(float)(it-catalog->envelopes.begin())+1;}
 values[5]=std::clamp(values[5],0.f,(float)catalog->envelopes.size());envelopeID=values[5]>0?catalog->envelopes[(int)values[5]-1].id:"";
 names={"Proyecto"};v={0};for(size_t i=0;i<catalog->envelopes.size();++i){names.push_back(catalog->envelopes[i].name);v.push_back((float)i+1);}SetParamElements(5,std::move(names),v,true);RaiseParamEvent(5,FF_EVENT_FLAG_VALUE);
}
void Wiper::runReader(){
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
            if(now-ackTime>.25&&now-render<.5){NSDictionary*d=@{@"time":@(render),@"sequence":@1,@"effect":@"wiper",@"source":@0,@"bpm":@(bpm.load()),@"barPhase":@(barPhase.load()),@"beatTime":@(beatTime.load()),@"inputWidth":@(inputW.load()),@"inputHeight":@(inputH.load()),@"mountWidth":@(mountW.load()),@"mountHeight":@(mountH.load()),@"gpuUploads":@(gpuUploads.load()),@"activeStep":@(activeStep.load()),@"mode":@(modeAck.load()),@"resolutionMismatch":@(inputW.load()!=mountW.load()||inputH.load()!=mountH.load())};NSData*b=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];[b writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"wiper-%@.json",instanceID]] options:NSDataWritingAtomic error:nil];[b writeToFile:[dir stringByAppendingPathComponent:@"receiver.json"] options:NSDataWritingAtomic error:nil];ackTime=now;}
        }
    }std::this_thread::sleep_for(std::chrono::milliseconds(10));}
}
static const char* vertexShader=R"(#version 410 core
layout(location=0)in vec2 position;layout(location=1)in vec4 bounds;
out vec2 sliceUV;out vec2 world;flat out vec2 sliceSize;
void main(){gl_Position=vec4(position,0,1);world=position;sliceSize=max(bounds.zw-bounds.xy,vec2(.000001));sliceUV=(position-bounds.xy)/sliceSize;}
)";
static const char* fragmentShader=R"(#version 410 core
in vec2 sliceUV;in vec2 world;flat in vec2 sliceSize;out vec4 color;
uniform sampler2D InputTexture;uniform sampler2D Curve;uniform vec2 MaxUV;uniform vec2 OutputSize;uniform float InputAspect;uniform int Scaling;
uniform vec2 Axis;uniform vec2 Projection;uniform float Progress;uniform float Length;uniform int Reverse;uniform int Mirrored;
void main(){
 if(Length<=0)discard;
 float coordinate=clamp((dot(world*OutputSize*.5,Axis)-Projection.x)/max(Projection.y-Projection.x,.000001),0,1);
 if(Mirrored!=0)coordinate=abs(coordinate-.5)*2;
 if(Reverse!=0)coordinate=1-coordinate;
 float local=(Progress*(1+Length)-coordinate)/Length;
 if(local<0||local>=1)discard;
 float level=texture(Curve,vec2((local*1024+.5)/1025,.5)).r;
 if(Scaling==0){color=vec4(level);return;}
 vec2 uv=sliceUV;float aspect=(sliceSize.x*OutputSize.x)/(sliceSize.y*OutputSize.y);
 if(InputAspect>aspect)uv.x=(uv.x-.5)*(aspect/InputAspect)+.5;else uv.y=(uv.y-.5)*(InputAspect/aspect)+.5;
 color=texture(InputTexture,clamp(uv,vec2(0),vec2(1))*MaxUV)*level;
}
)";
static const char* compositeVertex=R"(#version 410 core
layout(location=0)in vec4 vPosition;layout(location=1)in vec2 vUV;out vec2 uv;void main(){gl_Position=vPosition;uv=vUV;}
)";
static const char* compositeFragment=R"(#version 410 core
in vec2 uv;out vec4 color;uniform sampler2D InputTexture;uniform sampler2D Mask;uniform vec2 MaxUV;uniform int Live;uniform int Scaling;uniform float Amount;
void main(){vec4 dry=texture(InputTexture,uv*MaxUV);if(Live==0){color=dry;return;}vec4 wet=texture(Mask,uv);color=mix(dry,Scaling==0?dry*wet.r:wet,Amount);}
)";
void Wiper::rebuild(int w,int h){
 std::vector<Vertex>vertices;batches.clear();size_t row=0;
 for(id polygon in catalog->polygons){
  std::vector<P>points;for(id v in polygon)points.push_back({[v[0] floatValue],[v[1] floatValue]});if(points.size()>3&&hypot(points.back().x-points.front().x,points.back().y-points.front().y)<1e-7)points.pop_back();
  P axis{1,0};float best=0; // First longest edge keeps the rectangle's orientation on rotation.
  for(size_t i=0;i<points.size();++i){P a=points[i],b=points[(i+1)%points.size()];P d{(b.x-a.x)*w/2,(b.y-a.y)*h/2};float len=hypot(d.x,d.y);if(len>best+.01f){best=len;axis={d.x/len,d.y/len};}}
  if(values[12]>.5)axis={-axis.y,axis.x};
  float minP=1e30,maxP=-1e30,minX=points[0].x,maxX=minX;
  for(auto p:points){float projection=p.x*w/2*axis.x+p.y*h/2*axis.y;minP=std::min(minP,projection);maxP=std::max(maxP,projection);minX=std::min(minX,p.x);maxX=std::max(maxX,p.x);}
  WiperBatch b{(int)vertices.size(),(int)(*catalog->geometry)[row].size(),axis.x,axis.y,minP,maxP,(minX+maxX)/2};
  const auto&mesh=(*catalog->geometry)[row++];vertices.insert(vertices.end(),mesh.begin(),mesh.end());batches.push_back(b);
 }
 glBindBuffer(GL_ARRAY_BUFFER,vbo);glBufferData(GL_ARRAY_BUFFER,vertices.size()*sizeof(Vertex),vertices.data(),GL_STATIC_DRAW);
 cacheW=w;cacheH=h;geometryDirty=false;geometryCache=catalog;++gpuUploads;
}
FFResult Wiper::InitGL(const FFGLViewportStruct*vp){
 if(!geometryShader.Compile(vertexShader,fragmentShader)||!compositeShader.Compile(compositeVertex,compositeFragment)||!quad.Initialise()){DeInitGL();return FF_FAIL;}
 glGenVertexArrays(1,&vao);glGenBuffers(1,&vbo);glBindVertexArray(vao);glBindBuffer(GL_ARRAY_BUFFER,vbo);glEnableVertexAttribArray(0);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,sizeof(Vertex),nullptr);glEnableVertexAttribArray(1);glVertexAttribPointer(1,4,GL_FLOAT,GL_FALSE,sizeof(Vertex),(void*)sizeof(P));glBindBuffer(GL_ARRAY_BUFFER,0);glBindVertexArray(0);glGenTextures(1,&curveTexture);
 running=true;try{reader=std::thread(&Wiper::runReader,this);}catch(...){running=false;DeInitGL();return FF_FAIL;}return CFFGLPlugin::InitGL(vp);
}
FFResult Wiper::DeInitGL(){running=false;if(reader.joinable())reader.join();mask.Release();quad.Release();geometryShader.FreeGLResources();compositeShader.FreeGLResources();if(vao)glDeleteVertexArrays(1,&vao);if(vbo)glDeleteBuffers(1,&vbo);if(curveTexture)glDeleteTextures(1,&curveTexture);vao=vbo=curveTexture=0;batches.clear();uploadedCurve.clear();geometryCache.reset();geometryDirty=true;cacheW=cacheH=0;cursor=-1;triggerTime=-1;{std::lock_guard<std::mutex>lock(triggerMutex);pendingNext=0;held=false;}
 [[NSFileManager defaultManager]removeItemAtPath:[bridgeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"wiper-%@.json",instanceID]] error:nil];return FF_SUCCESS;}
FFResult Wiper::ProcessOpenGL(ProcessOpenGLStruct*p){
 if(!p||p->numInputTextures<1||!p->inputTextures||!p->inputTextures[0])return FF_FAIL;
 updateCatalog();bool live=catalog&&std::abs(nowSeconds()-latestFrame.load())<1;
 GLint vp[4];glGetIntegerv(GL_VIEWPORT,vp);int w=vp[2],h=vp[3];if(w<=0||h<=0||w>16384||h>16384)return FF_FAIL;
 inputW=p->inputTextures[0]->Width;inputH=p->inputTextures[0]->Height;mountW=catalog?(int)catalog->width:0;mountH=catalog?(int)catalog->height:0;modeAck=(int)values[2];
 if(mask.GetWidth()!=w||mask.GetHeight()!=h){mask.Release();if(!mask.Initialise(w,h))return FF_FAIL;}
 const GLenum caps[]={GL_CULL_FACE,GL_DEPTH_TEST,GL_SCISSOR_TEST,GL_STENCIL_TEST};GLboolean saved[4],writeMask[4];for(int i=0;i<4;++i){saved[i]=glIsEnabled(caps[i]);glDisable(caps[i]);}glGetBooleanv(GL_COLOR_WRITEMASK,writeMask);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);
 GLint savedVAO,savedArray,eqRGB,eqA;glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&savedVAO);glGetIntegerv(GL_ARRAY_BUFFER_BINDING,&savedArray);glGetIntegerv(GL_BLEND_EQUATION_RGB,&eqRGB);glGetIntegerv(GL_BLEND_EQUATION_ALPHA,&eqA);GLboolean blend=glIsEnabled(GL_BLEND);GLfloat clear[4];glGetFloatv(GL_COLOR_CLEAR_VALUE,clear);glDisable(GL_BLEND);
 int next;{std::lock_guard<std::mutex>lock(triggerMutex);next=pendingNext;pendingNext=0;held=false;}
 {
  ScopedFBOBinding target(mask.GetGLID(),ScopedFBOBinding::RB_REVERT);glViewport(0,0,w,h);glClearColor(0,0,0,0);glClear(GL_COLOR_BUFFER_BIT);
  if(live){
   if(geometryDirty||cacheW!=w||cacheH!=h)rebuild(w,h);
   const auto&seq=catalog->sequences[(int)values[1]];const auto&curve=values[5]>0?catalog->envelopes[(int)values[5]-1].values:catalog->envelope;
   if(curve!=uploadedCurve){ScopedSamplerActivation u(1);Scoped2DTextureBinding t(curveTexture);glTexImage2D(GL_TEXTURE_2D,0,GL_R32F,1025,1,0,GL_RED,GL_FLOAT,curve.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);uploadedCurve=curve;}
   std::vector<double>progress(seq.count,-1);const double now=nowSeconds();
   if(values[2]>.5){if(next>0){cursor=cursor<0?(next-1)%seq.count:(cursor+next)%seq.count;triggerTime=now;}if(cursor>=0&&triggerTime>=0){double phase=(now-triggerTime)/(4*pow(1./32,values[4]));if(phase>=0&&phase<1)progress[cursor]=phase;}activeStep=cursor;}
   else{double compression=1-.95*values[8],cycle=seq.total*compression;double phase=(double)values[6]*values[9];if(values[6]>=1)phase=std::nextafter((double)values[9],0.);double pos=(phase-floor(phase))*cycle,start=0;int index=seq.count-1;for(int i=0;i<seq.count;++i){double age=fmod(pos-start+cycle,cycle);if(age<seq.durations[i])progress[i]=age/seq.durations[i];if(pos>=start)index=i;start+=seq.durations[i]*compression;}activeStep=index;}
   ScopedShaderBinding shader(geometryShader.GetGLID());ScopedSamplerActivation u0(0);Scoped2DTextureBinding input(p->inputTextures[0]->Handle);ScopedSamplerActivation u1(1);Scoped2DTextureBinding lut(curveTexture);
   auto uv=GetMaxGLTexCoords(*p->inputTextures[0]);geometryShader.Set("InputTexture",0);geometryShader.Set("Curve",1);geometryShader.Set("MaxUV",uv.s,uv.t);geometryShader.Set("OutputSize",(float)w,(float)h);glUniform1f(geometryShader.FindUniform("InputAspect"),(float)inputW.load()/std::max(1,inputH.load()));glUniform1i(geometryShader.FindUniform("Scaling"),(int)values[0]);glUniform1f(geometryShader.FindUniform("Length"),values[7]);
   glBindVertexArray(vao);glEnable(GL_BLEND);glBlendEquation(GL_MAX);size_t stride=(batches.size()+7)/8;
   for(int step=0;step<seq.count;++step)if(progress[step]>=0){glUniform1f(geometryShader.FindUniform("Progress"),progress[step]);for(size_t row=0;row<batches.size();++row)if(seq.bits[step*stride+row/8]&(1<<(row%8))){const auto&b=batches[row];bool horizontal=std::abs(b.axisX)>=std::abs(b.axisY);bool reverse=(horizontal&&b.centerX<-.00001)^(values[10]>.5)^((values[11]>.5)&&(step%2==1));glUniform1i(geometryShader.FindUniform("Reverse"),reverse);glUniform1i(geometryShader.FindUniform("Mirrored"),horizontal&&std::abs(b.centerX)<.00001);geometryShader.Set("Axis",b.axisX,b.axisY);geometryShader.Set("Projection",b.minProjection,b.maxProjection);glDrawArrays(GL_TRIANGLES,b.first,b.count);}}
   glDisable(GL_BLEND);
  }else{cursor=-1;triggerTime=-1;activeStep=-1;}
 }
 glViewport(vp[0],vp[1],w,h);glClearColor(clear[0],clear[1],clear[2],clear[3]);glBlendEquationSeparate(eqRGB,eqA);
 {ScopedShaderBinding shader(compositeShader.GetGLID());ScopedSamplerActivation u0(0);Scoped2DTextureBinding input(p->inputTextures[0]->Handle);ScopedSamplerActivation u1(1);Scoped2DTextureBinding wet(mask.GetTextureInfo().Handle);auto uv=GetMaxGLTexCoords(*p->inputTextures[0]);compositeShader.Set("InputTexture",0);compositeShader.Set("Mask",1);compositeShader.Set("MaxUV",uv.s,uv.t);glUniform1i(compositeShader.FindUniform("Live"),live);glUniform1i(compositeShader.FindUniform("Scaling"),(int)values[0]);glUniform1f(compositeShader.FindUniform("Amount"),values[13]);quad.Draw();}
 if(blend)glEnable(GL_BLEND);for(int i=0;i<4;++i)if(saved[i])glEnable(caps[i]);glColorMask(writeMask[0],writeMask[1],writeMask[2],writeMask[3]);glBindVertexArray(savedVAO);glBindBuffer(GL_ARRAY_BUFFER,savedArray);if(live)lastRender=nowSeconds();return FF_SUCCESS;
}
