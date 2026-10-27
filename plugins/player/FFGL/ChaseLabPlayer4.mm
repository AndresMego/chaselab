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
#include "Echoes.h"
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
class ChaseLabLive : public CFFGLPlugin {
    FFGLShader geometryShader, compositeShader; FFGLScreenQuad quad; FFGLFBO mask;
    GLuint vao=0,vbo=0;
    std::atomic<bool> running{false}; std::thread reader; std::mutex meshMutex; Mesh latest,rendered;
    std::atomic<uint64_t> geometryBuilds{0},frameReads{0};
    std::atomic<uint64_t> gpuUploads{0};
    std::atomic<uint64_t> renderedSequence{0}; std::atomic<double> renderedTime{0};
    std::atomic<float> arenaBpm{0}, arenaPhase{0}; std::atomic<double> beatTime{0};
    float amount=1; int scaling=0,control=0;float sequenceChoice=0,stepPosition=0;int transport=0,rate=1;double playPosition=0,lastPlayTime=0;bool resetPlay=true;
    std::shared_ptr<PlayerCatalog> pendingCatalog,catalog;
    float envelopeChoice=0;std::string selectedEnvelopeID;
    std::atomic<int> renderedEnvelope{0},renderedEchoes{0};
    int echoes=0;
    std::string selectedID,display;
    std::vector<Vertex> uploaded;
    std::atomic<int> inputWidth{0},inputHeight{0},mountWidth{0},mountHeight{0},activeStep{0};
    std::atomic<bool> resolutionMismatch{false};
    NSString* instanceID=NSUUID.UUID.UUIDString;
    void updateCatalog();
    bool makeReader(); void readLoop();
public:
    ChaseLabLive() {
        SetMinInputs(1);SetMaxInputs(1);SetParamInfof(0,"Amount",FF_TYPE_STANDARD);
        SetOptionParamInfo(1,"Scaling",3,0);SetParamElementInfo(1,0,"Mask",0);SetParamElementInfo(1,1,"Fill",1);SetParamElementInfo(1,2,"Stretch",2);
        SetOptionParamInfo(2,"Control",2,0);SetParamElementInfo(2,0,"Editor",0);SetParamElementInfo(2,1,"Arena",1);
        SetOptionParamInfo(3,"Sequence",1,0);SetParamElementInfo(3,0,"Sin proyecto",0);
        SetParamInfof(4,"Step",FF_TYPE_INTEGER);SetParamRange(4,0,255);
        SetOptionParamInfo(5,"Advance",2,0);SetParamElementInfo(5,0,"BPM",0);SetParamElementInfo(5,1,"Manual",1);
        SetOptionParamInfo(6,"Rate",3,1);SetParamElementInfo(6,0,"1/4",1);SetParamElementInfo(6,1,"1/8",2);SetParamElementInfo(6,2,"1/16",4);SetParamVisibility(3,false,false);SetParamVisibility(4,false,false);SetParamVisibility(5,false,false);SetParamVisibility(6,false,false);
        SetOptionParamInfo(7,"Envelope",1,0);SetParamElementInfo(7,0,"Proyecto",0);
        SetParamInfof(8,"Echoes",FF_TYPE_INTEGER);SetParamRange(8,0,32);
    }
    ~ChaseLabLive() override { running=false;if(reader.joinable()) reader.join(); }
    FFResult InitGL(const FFGLViewportStruct* vp) override;
    FFResult DeInitGL() override;
    FFResult ProcessOpenGL(ProcessOpenGLStruct* p) override;
    FFResult SetFloatParameter(unsigned int i,float v) override {
        if(!std::isfinite(v))return FF_FAIL;
        if(i==0)amount=std::clamp(v,0.0f,1.0f);
        else if(i==1)scaling=std::clamp((int)std::round(v),0,2);
        else if(i==2){int next=std::clamp((int)std::round(v),0,1);if(next!=control){resetPlay=true;control=next;}SetParamVisibility(3,control==1,true);SetParamVisibility(4,control==1,true);SetParamVisibility(5,control==1,true);SetParamVisibility(6,control==1 && transport==0,true);}
        else if(i==3){float next=std::clamp(std::round(v),0.0f,catalog?(float)catalog->sequences.size()-1:127.0f);if(next!=sequenceChoice){sequenceChoice=next;resetPlay=true;}selectedID.clear();if(catalog && sequenceChoice<catalog->sequences.size())selectedID=catalog->sequences[(int)sequenceChoice].id;}
        else if(i==4){float next=std::clamp(std::round(v),0.0f,catalog?(float)catalog->sequences[(int)sequenceChoice].count-1:255.0f);if(next!=stepPosition){stepPosition=next;resetPlay=true;}if(next!=v)RaiseParamEvent(4,FF_EVENT_FLAG_VALUE);}
        else if(i==5){int next=std::clamp((int)std::round(v),0,1);if(next!=transport){transport=next;resetPlay=true;}SetParamVisibility(6,control==1 && transport==0,true);}
        else if(i==6){int next=v<1.5?1:v<3?2:4;if(next!=rate){rate=next;resetPlay=true;}}
        else if(i==7){envelopeChoice=std::clamp(std::round(v),0.0f,catalog?(float)catalog->envelopes.size():512.0f);selectedEnvelopeID.clear();if(catalog && envelopeChoice>0)selectedEnvelopeID=catalog->envelopes[(int)envelopeChoice-1].id;}
        else if(i==8)echoes=(int)std::round(std::clamp(v,0.0f,32.0f));
        else return FF_FAIL;return FF_SUCCESS;
    }
    float GetFloatParameter(unsigned int i) override {return i==0?amount:i==1?scaling:i==2?control:i==3?sequenceChoice:i==4?stepPosition:i==5?transport:i==6?rate:i==7?envelopeChoice:i==8?(float)echoes:0;}
    char* GetParameterDisplay(unsigned int i) override {
        if(i==4){display="Step "+std::to_string(activeStep.load()+1);return display.data();}
        return CFFGLPlugin::GetParameterDisplay(i);
    }
    void SetBeatInfo(float tempo,float phase) override {
        CFFGLPlugin::SetBeatInfo(tempo,phase);
        if(std::isfinite(tempo) && tempo>=20 && tempo<=300 && std::isfinite(phase)) {
            arenaBpm=tempo;arenaPhase=phase-floor(phase);beatTime=nowSeconds();
        }
    }
};
static CFFGLPluginInfo info(PluginFactory<ChaseLabLive>,"CLP4","CL Player",2,1,0,4,FF_EFFECT,"Independent Sequence and Step player","ChaseLab Player 0.4 - editor catalog bridge");
void ChaseLabLive::updateCatalog() {
    std::shared_ptr<PlayerCatalog> incoming;
    {std::unique_lock<std::mutex> lock(meshMutex,std::try_to_lock);if(lock.owns_lock())incoming=pendingCatalog;}
    if(!incoming || incoming==catalog)return;
    catalog=incoming;
    if(!selectedID.empty()) {
        auto it=std::find_if(catalog->sequences.begin(),catalog->sequences.end(),[&](const auto& s){return s.id==selectedID;});
        sequenceChoice=it==catalog->sequences.end()?0:(float)(it-catalog->sequences.begin());
    }
    sequenceChoice=std::clamp(sequenceChoice,0.0f,(float)catalog->sequences.size()-1);selectedID=catalog->sequences[(int)sequenceChoice].id;
    stepPosition=std::min(stepPosition,(float)catalog->sequences[(int)sequenceChoice].count-1);RaiseParamEvent(4,FF_EVENT_FLAG_VALUE);
    std::vector<std::string> names;std::vector<float> values;
    for(size_t i=0;i<catalog->sequences.size();++i){names.push_back(catalog->sequences[i].name.empty()?"Sin nombre":catalog->sequences[i].name);values.push_back((float)i);}
    SetParamElements(3,std::move(names),values,true);RaiseParamEvent(3,FF_EVENT_FLAG_VALUE);
    if(!selectedEnvelopeID.empty()){
        auto it=std::find_if(catalog->envelopes.begin(),catalog->envelopes.end(),[&](const auto& e){return e.id==selectedEnvelopeID;});
        envelopeChoice=it==catalog->envelopes.end()?0:(float)(it-catalog->envelopes.begin())+1;
    }
    envelopeChoice=std::clamp(envelopeChoice,0.0f,(float)catalog->envelopes.size());selectedEnvelopeID=envelopeChoice>0?catalog->envelopes[(int)envelopeChoice-1].id:"";
    std::vector<std::string> envelopeNames{"Proyecto"};std::vector<float> envelopeValues{0};
    for(size_t i=0;i<catalog->envelopes.size();++i){envelopeNames.push_back(catalog->envelopes[i].name);envelopeValues.push_back((float)i+1);}
    SetParamElements(7,std::move(envelopeNames),envelopeValues,true);RaiseParamEvent(7,FF_EVENT_FLAG_VALUE);
}
static const char* geometryVertex=R"(#version 410 core
layout(location=0) in vec2 position;layout(location=1) in vec4 sliceBounds;
out vec2 sliceUV;flat out vec2 sliceSize;
void main(){gl_Position=vec4(position,0,1);sliceSize=max(sliceBounds.zw-sliceBounds.xy,vec2(0.000001));sliceUV=(position-sliceBounds.xy)/sliceSize;}
)";
static const char* geometryFragment=R"(#version 410 core
in vec2 sliceUV;flat in vec2 sliceSize;out vec4 color;
uniform float Intensity;uniform sampler2D InputTexture;uniform vec2 MaxUV;uniform vec2 OutputSize;uniform float InputAspect;uniform int Scaling;
void main(){
 if(Scaling==0){color=vec4(Intensity,Intensity,Intensity,1);return;}
 vec2 uv=sliceUV;
 if(Scaling==1){float aspect=(sliceSize.x*OutputSize.x)/(sliceSize.y*OutputSize.y);
 if(InputAspect>aspect)uv.x=(uv.x-0.5)*(aspect/InputAspect)+0.5;
 else uv.y=(uv.y-0.5)*(InputAspect/aspect)+0.5;}
 color=texture(InputTexture,clamp(uv,vec2(0),vec2(1))*MaxUV)*Intensity;
}
)";
static const char* compositeVertex=R"(#version 410 core
layout(location=0) in vec4 vPosition;layout(location=1) in vec2 vUV;
out vec2 uv;void main(){gl_Position=vPosition;uv=vUV;}
)";
static const char* compositeFragment=R"(#version 410 core
in vec2 uv;out vec4 color;uniform sampler2D Mask;uniform sampler2D InputTexture;
uniform vec2 MaxUV;uniform float Amount;uniform int IsSource;uniform int Live;uniform int Scaling;
void main(){float m=texture(Mask,uv).r;
if(IsSource!=0){float a=Live!=0 ? m*Amount:0; color=vec4(a);}
else {vec4 dry=texture(InputTexture,uv*MaxUV);if(Live==0){color=dry;return;}
color=Scaling==0 ? dry*mix(1.0,m,Amount):mix(dry,texture(Mask,uv),Amount);}}
)";
bool ChaseLabLive::makeReader() {
    try { running=true;reader=std::thread(&ChaseLabLive::readLoop,this);return true; } catch(...) { running=false;return false; }
}
void ChaseLabLive::readLoop() {
    double lastAck=0; uint64_t seen=0;
    ino_t catalogInode=0;timespec catalogModification{};std::shared_ptr<PlayerCatalog> previousCatalog;
    NSArray* cachedPolygons=nil;std::vector<Vertex> cachedVertices;
    ino_t readInode=0;off_t readSize=-1;timespec readModification{};
    while(running) {
        @autoreleasepool {
            NSString* dir=bridgeDirectory(); struct stat st;
            if(lstat(dir.fileSystemRepresentation,&st)==0 && S_ISDIR(st.st_mode) && st.st_uid==getuid() && !(st.st_mode&0077)) {
                NSString* catalogPath=[dir stringByAppendingPathComponent:@"catalog.json"];
                if(lstat(catalogPath.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode) && st.st_uid==getuid() && st.st_size>0 && st.st_size<32*1024*1024 && (st.st_ino!=catalogInode || st.st_mtimespec.tv_sec!=catalogModification.tv_sec || st.st_mtimespec.tv_nsec!=catalogModification.tv_nsec)) {
                    catalogInode=st.st_ino;catalogModification=st.st_mtimespec;
                    auto parsed=parseCatalog([NSData dataWithContentsOfFile:catalogPath options:NSDataReadingUncached error:nil],previousCatalog);
                    if(parsed){previousCatalog=parsed;std::lock_guard<std::mutex> lock(meshMutex);pendingCatalog=parsed;}
                }
                NSString* path=[dir stringByAppendingPathComponent:@"frame.json"];
                if(lstat(path.fileSystemRepresentation,&st)==0 && S_ISREG(st.st_mode) && st.st_uid==getuid() && st.st_size>0 && st.st_size<=4*1024*1024 && (st.st_ino!=readInode || st.st_size!=readSize || st.st_mtimespec.tv_sec!=readModification.tv_sec || st.st_mtimespec.tv_nsec!=readModification.tv_nsec)) {
                    readInode=st.st_ino;readSize=st.st_size;readModification=st.st_mtimespec;++frameReads;
                    NSData* data=[NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:nil];
                    id root=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
                    if([root isKindOfClass:NSDictionary.class]) {
                        id ver=root[@"version"], seq=root[@"sequence"], time=root[@"time"], intensity=root[@"intensity"], enabled=root[@"enabled"], polys=root[@"polygons"];
                        if([ver isKindOfClass:NSNumber.class] && [ver intValue]==1 && [seq isKindOfClass:NSNumber.class] && [time isKindOfClass:NSNumber.class] && [intensity isKindOfClass:NSNumber.class] && [enabled isKindOfClass:NSNumber.class] && [polys isKindOfClass:NSArray.class] && [polys count]<=256 && [seq unsignedLongLongValue]!=seen) {
                            seen=[seq unsignedLongLongValue];
                            Mesh m;double frameStep;if([root[@"sequenceID"] isKindOfClass:NSString.class] && [root[@"sequenceID"] length]<=128 && finiteNumber(root[@"step"],frameStep) && frameStep==floor(frameStep) && frameStep>=0 && frameStep<256){m.sequenceID=[root[@"sequenceID"] UTF8String];m.step=(int)frameStep;}double phase;if(finiteNumber(root[@"phase"],phase) && phase>=0 && phase<=1)m.phase=(float)phase;if([root[@"playing"] isKindOfClass:NSNumber.class])m.playing=[root[@"playing"] boolValue];if([root[@"session"] isKindOfClass:NSString.class])m.session=[root[@"session"] UTF8String];m.sequence=[seq unsignedLongLongValue];m.time=[time doubleValue];m.intensity=[intensity floatValue];bool valid=std::isfinite(m.time) && std::isfinite(m.intensity) && m.intensity>=0 && m.intensity<=1 && std::abs(nowSeconds()-m.time)<1;
                            if(![enabled boolValue]) m.time=0;
                            const bool cached=cachedPolygons && [cachedPolygons isEqualToArray:polys];
                            if(cached) m.vertices=cachedVertices;
                            size_t total=0;
                            if(!cached) for(id polygon in polys) {
                                if(!valid) break;
                                if(![polygon isKindOfClass:NSArray.class] || [polygon count]<3 || [polygon count]>1024 || (total += [polygon count])>16384) { valid=false;break; }
                                std::vector<P> points;
                                for(id v in polygon) {
                                    if(![v isKindOfClass:NSArray.class] || [v count]!=2 || ![v[0] isKindOfClass:NSNumber.class] || ![v[1] isKindOfClass:NSNumber.class]) {valid=false;break;}
                                    P p{[v[0] floatValue],[v[1] floatValue]};
                                    if(!std::isfinite(p.x)||!std::isfinite(p.y)||std::abs(p.x)>10000||std::abs(p.y)>10000) {valid=false;break;} points.push_back(p);
                                }
                                if(valid) {
                                    std::vector<P> triangles;
                                    if(!triangulate(points,triangles)) valid=false;
                                    else {
                                        float minX=points[0].x,maxX=minX,minY=points[0].y,maxY=minY;
                                        for(P p:points){minX=std::min(minX,p.x);maxX=std::max(maxX,p.x);minY=std::min(minY,p.y);maxY=std::max(maxY,p.y);}
                                        for(P p:triangles)m.vertices.push_back({p,minX,minY,maxX,maxY});
                                    }
                                }
                            }
                            if(valid) {
                                if(!cached) { cachedPolygons=[polys copy];cachedVertices=m.vertices;++geometryBuilds; }
                                std::lock_guard<std::mutex> lock(meshMutex);latest=std::move(m);
                            }
                        }
                    }
                }
                double t=nowSeconds(),rt=renderedTime.load();
                if(t-lastAck>0.25 && t-rt<0.5 && renderedSequence.load()>0) {
                    NSDictionary* ack=@{@"time":@(rt),@"sequence":@(renderedSequence.load()),@"pid":@(getpid()),@"source":@(SOURCE_MODE),@"bpm":@(arenaBpm.load()),@"barPhase":@(arenaPhase.load()),@"beatTime":@(beatTime.load()),@"protocol":@2,@"geometryBuilds":@(geometryBuilds.load()),@"frameReads":@(frameReads.load()),@"playerVersion":@4,@"echoes":@(renderedEchoes.load()),@"envelopeIndex":@(renderedEnvelope.load()),@"activeStep":@(activeStep.load()),@"gpuUploads":@(gpuUploads.load()),@"inputWidth":@(inputWidth.load()),@"inputHeight":@(inputHeight.load()),@"mountWidth":@(mountWidth.load()),@"mountHeight":@(mountHeight.load()),@"resolutionMismatch":@(resolutionMismatch.load())};
                    NSData* d=[NSJSONSerialization dataWithJSONObject:ack options:0 error:nil];
                    NSString* ackPath=[dir stringByAppendingPathComponent:@"receiver.json"];
                    [d writeToFile:ackPath options:NSDataWritingAtomic error:nil];
                    [d writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"player-%@.json",instanceID]] options:NSDataWritingAtomic error:nil];lastAck=t;
                }
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
}
FFResult ChaseLabLive::InitGL(const FFGLViewportStruct* vp) {
    if(!geometryShader.Compile(geometryVertex,geometryFragment) || !compositeShader.Compile(compositeVertex,compositeFragment) || !quad.Initialise()) { DeInitGL();return FF_FAIL; }
    glGenVertexArrays(1,&vao);glGenBuffers(1,&vbo);
    glBindVertexArray(vao);glBindBuffer(GL_ARRAY_BUFFER,vbo);glEnableVertexAttribArray(0);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,sizeof(Vertex),nullptr);glEnableVertexAttribArray(1);glVertexAttribPointer(1,4,GL_FLOAT,GL_FALSE,sizeof(Vertex),(void*)sizeof(P));glBindBuffer(GL_ARRAY_BUFFER,0);glBindVertexArray(0);
    if(!makeReader()) {DeInitGL();return FF_FAIL;}
    return CFFGLPlugin::InitGL(vp);
}
FFResult ChaseLabLive::DeInitGL() {
    running=false;if(reader.joinable()) reader.join();
    mask.Release();quad.Release();geometryShader.FreeGLResources();compositeShader.FreeGLResources();uploaded.clear();
    [[NSFileManager defaultManager]removeItemAtPath:[bridgeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"player-%@.json",instanceID]] error:nil];
    if(vbo) glDeleteBuffers(1,&vbo);if(vao) glDeleteVertexArrays(1,&vao);vbo=vao=0;return FF_SUCCESS;
}
FFResult ChaseLabLive::ProcessOpenGL(ProcessOpenGLStruct* p) {
    if(!p || (!SOURCE_MODE && (p->numInputTextures<1 || !p->inputTextures || !p->inputTextures[0]))) return FF_FAIL;
    {std::unique_lock<std::mutex> lock(meshMutex,std::try_to_lock);if(lock.owns_lock() && latest.sequence!=rendered.sequence) rendered=latest;}
    updateCatalog();
    bool live=std::abs(nowSeconds()-rendered.time)<1.0;
    Mesh output=rendered;
    const std::vector<float>* chosenCurve=catalog && envelopeChoice>0?&catalog->envelopes[(int)envelopeChoice-1].values:catalog?&catalog->envelope:nullptr;
    renderedEnvelope=(int)envelopeChoice;renderedEchoes=echoes;
    struct Batch {GLint first;GLsizei count;float intensity;};
    std::vector<Batch> batches;
    auto buildSequence=[&](const PlayerSequence& sequence,int index,double phase,bool hold) {
        const auto levels=echoLevels(sequence.durations,sequence.bits,catalog->geometry->size(),index,phase,echoes,hold,*chosenCurve);
        output.vertices.clear();
        for(size_t r=0;r<levels.size();++r)if(levels[r]>=0){
            const auto& vertices=(*catalog->geometry)[r];GLint first=(GLint)output.vertices.size();
            output.vertices.insert(output.vertices.end(),vertices.begin(),vertices.end());
            if(!batches.empty() && batches.back().intensity==levels[r])batches.back().count+=(GLsizei)vertices.size();
            else batches.push_back({first,(GLsizei)vertices.size(),levels[r]});
        }
    };
    if(control==0 && envelopeChoice>0 && catalog && rendered.session==catalog->session && rendered.playing){
        const double sample=std::clamp((double)rendered.phase,0.0,1.0)*1024;const int base=std::min(1023,(int)sample);
        output.intensity=(*chosenCurve)[base]+((*chosenCurve)[base+1]-(*chosenCurve)[base])*(sample-base);
    }
    if(control==0 && echoes>1 && catalog && rendered.session==catalog->session && rendered.step>=0){
        auto it=std::find_if(catalog->sequences.begin(),catalog->sequences.end(),[&](const auto& seq){return seq.id==rendered.sequenceID;});
        if(it!=catalog->sequences.end() && rendered.step<it->count){activeStep=rendered.step;buildSequence(*it,rendered.step,rendered.phase,!rendered.playing);}
    }
    if(control==1) {
        live=live && catalog && rendered.session==catalog->session;
        output.vertices.clear();
        if(live){
            const auto& sequence=catalog->sequences[(int)sequenceChoice];
            const double t=nowSeconds();
            if(resetPlay || lastPlayTime==0){playPosition=0;for(int i=0;i<std::min((int)stepPosition,sequence.count-1);++i)playPosition+=sequence.durations[i];resetPlay=false;lastPlayTime=t;}
            if(transport==0){double tempo=arenaBpm.load();if(tempo<20 || tempo>300)tempo=120;playPosition+=std::clamp(t-lastPlayTime,0.0,1.0)*tempo/60*rate;}
            lastPlayTime=t;
            double position=std::fmod(playPosition,sequence.total),start=0;int index=sequence.count-1;
            if(transport==1){index=std::min((int)stepPosition,sequence.count-1);position=0;}
            else for(int i=0;i<sequence.count;++i){if(position<start+sequence.durations[i]){index=i;break;}start+=sequence.durations[i];}
            activeStep=index;
            double phase=std::clamp((position-start)/sequence.durations[index],0.0,1.0);
            buildSequence(sequence,index,phase,transport==1);
        }
    }
    if(!live){lastPlayTime=0;resetPlay=true;}
    inputWidth=p->inputTextures[0]->Width;inputHeight=p->inputTextures[0]->Height;
    mountWidth=catalog?(int)catalog->width:0;mountHeight=catalog?(int)catalog->height:0;
    resolutionMismatch=catalog && (inputWidth.load()!=mountWidth.load() || inputHeight.load()!=mountHeight.load());
    GLint viewport[4];glGetIntegerv(GL_VIEWPORT,viewport);
    if(viewport[2]<=0 || viewport[3]<=0 || viewport[2]>16384 || viewport[3]>16384) return FF_FAIL;
    if(mask.GetWidth()!=viewport[2] || mask.GetHeight()!=viewport[3]) {mask.Release();if(!mask.Initialise(viewport[2],viewport[3])) return FF_FAIL;}
    GLboolean blend=glIsEnabled(GL_BLEND);GLint blendRGB,blendAlpha;
    glGetIntegerv(GL_BLEND_EQUATION_RGB,&blendRGB);glGetIntegerv(GL_BLEND_EQUATION_ALPHA,&blendAlpha);
    glDisable(GL_BLEND);
    GLfloat clearColor[4];glGetFloatv(GL_COLOR_CLEAR_VALUE,clearColor);
    {
        ScopedFBOBinding target(mask.GetGLID(),ScopedFBOBinding::RB_REVERT);
        glViewport(0,0,viewport[2],viewport[3]);glClearColor(0,0,0,0);glClear(GL_COLOR_BUFFER_BIT);
        if(live && !output.vertices.empty()) {
            ScopedShaderBinding program(geometryShader.GetGLID());glUniform1f(geometryShader.FindUniform("Intensity"),output.intensity);
            glUniform1i(geometryShader.FindUniform("Scaling"),SOURCE_MODE ? 0:scaling);
            FFGLTexCoords inputUV{1,1};if(!SOURCE_MODE)inputUV=GetMaxGLTexCoords(*p->inputTextures[0]);
            ScopedSamplerActivation geometryUnit(0);Scoped2DTextureBinding geometryInput(SOURCE_MODE ? 0:p->inputTextures[0]->Handle);
            geometryShader.Set("InputTexture",0);geometryShader.Set("MaxUV",inputUV.s,inputUV.t);geometryShader.Set("OutputSize",(float)viewport[2],(float)viewport[3]);
            glUniform1f(geometryShader.FindUniform("InputAspect"),SOURCE_MODE ? 1:(float)p->inputTextures[0]->Width/p->inputTextures[0]->Height);
            glBindVertexArray(vao);glBindBuffer(GL_ARRAY_BUFFER,vbo);if(uploaded.size()!=output.vertices.size() || std::memcmp(uploaded.data(),output.vertices.data(),output.vertices.size()*sizeof(Vertex))!=0) {glBufferData(GL_ARRAY_BUFFER,output.vertices.size()*sizeof(Vertex),output.vertices.data(),GL_DYNAMIC_DRAW);uploaded=output.vertices;++gpuUploads;}
            if(batches.empty())batches.push_back({0,(GLsizei)output.vertices.size(),output.intensity});
            if(scaling==0){glEnable(GL_BLEND);glBlendEquation(GL_MAX);}
            for(const auto& batch:batches){glUniform1f(geometryShader.FindUniform("Intensity"),batch.intensity);glDrawArrays(GL_TRIANGLES,batch.first,batch.count);}
            glDisable(GL_BLEND);glBlendEquationSeparate(blendRGB,blendAlpha);
            glBindBuffer(GL_ARRAY_BUFFER,0);glBindVertexArray(0);
        }
    }
    glClearColor(clearColor[0],clearColor[1],clearColor[2],clearColor[3]);glViewport(viewport[0],viewport[1],viewport[2],viewport[3]);
    {
        ScopedShaderBinding program(compositeShader.GetGLID());
        ScopedSamplerActivation unit0(0);Scoped2DTextureBinding input(SOURCE_MODE ? mask.GetTextureInfo().Handle:p->inputTextures[0]->Handle);
        ScopedSamplerActivation unit1(1);Scoped2DTextureBinding maskTexture(mask.GetTextureInfo().Handle);
        compositeShader.Set("Mask",1);compositeShader.Set("InputTexture",0);glUniform1i(compositeShader.FindUniform("IsSource"),SOURCE_MODE);glUniform1i(compositeShader.FindUniform("Live"),live ? 1:0);glUniform1f(compositeShader.FindUniform("Amount"),amount);glUniform1i(compositeShader.FindUniform("Scaling"),scaling);
        FFGLTexCoords uv{1,1};if(!SOURCE_MODE) uv=GetMaxGLTexCoords(*p->inputTextures[0]);compositeShader.Set("MaxUV",uv.s,uv.t);quad.Draw();
    }
    if(blend) glEnable(GL_BLEND);
    if(live) {renderedSequence=rendered.sequence;renderedTime=nowSeconds();}
    return FF_SUCCESS;
}
