// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#import <Foundation/Foundation.h>
#include <OpenGL/OpenGL.h>
#include <FFGLSDK.h>
#include <dlfcn.h>
#include <thread>
#include <iostream>
#include <cmath>
#include <cstring>
#include <algorithm>
#include "../FFGL/Echoes.h"
static float asFloat(FFMixed m){float f;memcpy(&f,&m.UIntValue,sizeof(f));return f;}
#include <unistd.h>
static void require(bool v,const char* m){if(!v){std::cerr<<"FAIL: "<<m<<"\n";exit(1);}}
int main(int argc,char**argv){@autoreleasepool{
 require(argc==2,"plugin path");
 std::vector<float> fall(1025),rise(1025);for(int i=0;i<=1024;++i){fall[i]=1-i/1024.0f;rise[i]=i/1024.0f;}
 auto near=[](float a,float b){return std::abs(a-b)<.00001;};
 auto l=echoLevels({1,1,1,1},{1,2,4,8},4,2,.5,4,false,fall);
 require(near(l[0],.375)&&near(l[1],.625)&&near(l[2],.875)&&near(l[3],.125),"four-step lifetime and wrap");
 auto zero=echoLevels({1,1,1,1},{1,2,4,8},4,2,.5,0,false,fall),one=echoLevels({1,1,1,1},{1,2,4,8},4,2,.5,1,false,fall);
 require(zero==one && zero[0]<0 && near(zero[2],.5),"zero/one single-step fade");
 l=echoLevels({1,2,4,1},{1,2,4,8},4,2,.5,2,false,fall);require(near(l[2],.6)&&near(l[1],1.0f/3),"weighted step durations");
 l=echoLevels({1},{1},1,0,.5,4,false,fall);require(near(l[0],.875),"short sequence wrap");
 l=echoLevels({1},{1},1,0,.5,4,false,rise);require(near(l[0],.875),"repeated slice max with rising curve");
 l=echoLevels({1,1},{1,2},2,1,.5,4,true,fall);require(l[0]==1&&l[1]==1,"manual trail hold");
 l=echoLevels({1,1},{0,0},2,1,.5,32,false,fall);require(l[0]<0&&l[1]<0,"empty steps");
 std::cout<<"PASS: echo lifetimes, wrap, weighted durations, short loops, repeated slices, pause and empty steps\n";

 char temp[]="/private/tmp/chaselab-mapper-test.XXXXXX";require(mkdtemp(temp),"private directory");setenv("CHASELAB_BRIDGE_DIR",temp,1);NSString*dir=[NSString stringWithUTF8String:temp];
 CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};CGLPixelFormatObj fmt;GLint n;CGLContextObj ctx;require(CGLChoosePixelFormat(attrs,&fmt,&n)==kCGLNoError,"format");require(CGLCreateContext(fmt,nullptr,&ctx)==kCGLNoError,"context");CGLDestroyPixelFormat(fmt);CGLSetCurrentContext(ctx);
 void*lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!lib)std::cerr<<dlerror()<<"\n";require(lib,"dlopen");auto entry=(FF_Main_FuncPtr)dlsym(lib,"plugMain");require(entry,"entry");FFMixed a{};require(entry(FF_INITIALISE_V2,a,nullptr).UIntValue==FF_SUCCESS,"initialise");require(entry(FF_GET_NUM_PARAMETERS,a,nullptr).UIntValue==9,"nine parameters");a.UIntValue=1;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_OPTION,"Scaling option");
 GLuint target,out,input;glGenTextures(1,&out);glBindTexture(GL_TEXTURE_2D,out);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glGenFramebuffers(1,&target);glBindFramebuffer(GL_FRAMEBUFFER,target);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,out,0);require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"FBO");
 std::vector<unsigned char> image(128*64*4,255);auto upload=[&](int alpha){for(int y=0;y<32;++y)for(int x=0;x<64;++x){int i=(y*128+x)*4;image[i]=std::lround(255.0*x/63);image[i+1]=std::lround(255.0*y/31);image[i+2]=32;image[i+3]=alpha;}glBindTexture(GL_TEXTURE_2D,input);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,128,64,0,GL_RGBA,GL_UNSIGNED_BYTE,image.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glBindTexture(GL_TEXTURE_2D,0);};glGenTextures(1,&input);upload(255);
 FFGLTextureStruct texture{64,32,128,64,input};FFGLTextureStruct*ptr=&texture;ProcessOpenGLStruct process{1,&ptr,target};FFGLViewportStruct vp{0,0,64,64};a.PointerValue=&vp;void*instance=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(instance && instance!=(void*)(uintptr_t)FF_FAIL,"instantiate");
 auto set=[&](int index,float value){SetParameterStruct s{};s.ParameterNumber=index;memcpy(&s.NewParameterValue.UIntValue,&value,sizeof(value));a.PointerValue=&s;require(entry(FF_SET_PARAMETER,a,instance).UIntValue==FF_SUCCESS,"parameter");};
 int seq=0;NSArray*polygons=@[@[@[@-1,@-1],@[@0,@-1],@[@0,@0],@[@-1,@0]],@[@[@0.25,@0],@[@1,@0],@[@1,@1],@[@0.25,@1]]];
 auto write=[&](float intensity,bool enabled){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(intensity),@"enabled":@(enabled),@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"fixture");std::this_thread::sleep_for(std::chrono::milliseconds(60));};
 auto render=[&](){glBindFramebuffer(GL_FRAMEBUFFER,target);glViewport(0,0,64,64);a.PointerValue=&process;require(entry(FF_PROCESS_OPENGL,a,instance).UIntValue==FF_SUCCESS,"render");glFinish();require(glGetError()==GL_NO_ERROR,"GL state/error");};
 auto sample=[&](int x,int y,int r,int g,int alpha){unsigned char p[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,p);if(abs(p[0]-r)>3||abs(p[1]-g)>3||abs(p[3]-alpha)>3){std::cerr<<"at "<<x<<","<<y<<": "<<(int)p[0]<<","<<(int)p[1]<<","<<(int)p[3]<<" expected "<<r<<","<<g<<","<<alpha<<"\n";require(false,"pixel");}};
 auto expected=[&](int x,int y,int mode,double bx,double by,double bw,double bh,float level=1,int alpha=255){double u=(x+.5)/64,v=(y+.5)/64;if(mode){u=((x+.5)-bx)/bw;v=((y+.5)-by)/bh;if(mode==1){double aspect=bw/bh;if(2>aspect)u=(u-.5)*(aspect/2)+.5;else v=(v-.5)*(2/aspect)+.5;}}int sx=std::clamp((int)floor(u*64),0,63),sy=std::clamp((int)floor(v*32),0,31);sample(x,y,lround(lround(255.0*sx/63)*level),lround(lround(255.0*sy/31)*level),lround(alpha*level));};
 set(0,1);for(int mode=0;mode<3;++mode){set(1,mode);write(1,true);render();expected(4,8,mode,0,0,32,32);expected(26,26,mode,0,0,32,32);expected(44,40,mode,40,32,24,32);sample(34,16,0,0,0);std::cout<<"PASS: mode "<<mode<<" per-slice UV, centered crop, padding, orientation and outside alpha\n";}
 set(1,2);write(.5,true);render();expected(4,8,2,0,0,32,32,.5);set(0,0);render();expected(4,8,0,0,0,32,32);expected(34,16,0,0,0,32,32);set(0,1);
 upload(128);write(1,true);render();expected(4,8,2,0,0,32,32,1,128);upload(255);
 write(1,false);render();expected(34,16,0,0,0,32,32);write(1,true);std::this_thread::sleep_for(std::chrono::milliseconds(1100));render();expected(34,16,0,0,0,32,32);std::cout<<"PASS: envelope, Amount bypass, transparent input, disabled/stale pass-through\n";
 polygons=@[@[@[@-1,@-1],@[@1,@-1],@[@1,@0],@[@0,@0],@[@0,@1],@[@-1,@1]]];set(1,2);write(1,true);render();sample(48,48,0,0,0);expected(16,48,2,0,0,64,64);std::cout<<"PASS: concave polygon clipping\n";
 // Independent instances retain their own scaling selection.
 a.PointerValue=&vp;void*other=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(other && other!=(void*)(uintptr_t)FF_FAIL,"second instance");a.UIntValue=1;require(asFloat(entry(FF_GET_PARAMETER,a,other))==0,"new instance defaults Mask");a.UIntValue=1;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==2,"first instance retains Stretch");entry(FF_DEINSTANTIATE_GL,a,other);
 for(int i=0;i<90;++i){set(1,i%3);write(1,true);render();}std::cout<<"PASS: repeated live mode changes and independent instances\n";

 // Catalog playback is independent of the editor's current step.
 polygons=@[@[@[@-1,@-1],@[@0,@-1],@[@0,@0],@[@-1,@0]],@[@[@0.25,@0],@[@1,@0],@[@1,@1],@[@0.25,@1]]];
 NSMutableArray* curve=[NSMutableArray array];for(int i=0;i<=1024;++i)[curve addObject:@1];
 NSDictionary*seqA=@{@"id":@"A",@"name":@"First",@"count":@2,@"bits":@"AQI=",@"durations":@[@1,@4]};
 NSDictionary*seqB=@{@"id":@"B",@"name":@"Second",@"count":@1,@"bits":@"Aw==",@"durations":@[@1]};
 NSMutableDictionary*catalog=[@{@"version":@1,@"session":@"test-session",@"width":@64,@"height":@32,@"polygons":polygons,@"sequences":@[seqA,seqB],@"envelope":curve}mutableCopy];
 auto writeCatalog=[&](){NSData*d=[NSJSONSerialization dataWithJSONObject:catalog options:0 error:nil];require([d writeToFile:[dir stringByAppendingPathComponent:@"catalog.json"] options:NSDataWritingAtomic error:nil],"catalog fixture");std::this_thread::sleep_for(std::chrono::milliseconds(80));};
 auto heartbeat=[&](NSString*session){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"session":session,@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@1,@"enabled":@YES,@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"heartbeat");std::this_thread::sleep_for(std::chrono::milliseconds(60));};
 writeCatalog();heartbeat(@"test-session");set(1,0);set(2,1);set(5,1);set(3,0);set(4,0);render();expected(4,8,0,0,0,32,32);sample(44,40,0,0,0);
 set(4,0);render();expected(4,8,0,0,0,32,32);sample(44,40,0,0,0);
 set(4,1);render();sample(4,8,0,0,0);expected(44,40,0,0,0,32,32);
 set(4,1);render();sample(4,8,0,0,0);expected(44,40,0,0,0,32,32);
 set(3,1);render();expected(4,8,0,0,0,32,32);expected(44,40,0,0,0,32,32);
 std::cout<<"PASS: independent Sequence and integer Step selection\n";
 // Reordering preserves selected sequence by UUID, and the host can refresh its labels.
 set(3,0);catalog[@"sequences"]=@[seqB,seqA];writeCatalog();heartbeat(@"test-session");render();a.UIntValue=3;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==1,"selected ID preserved after reorder");
 GetParameterElementNameStruct label{3,1};a.PointerValue=&label;require(strcmp((char*)entry(FF_GET_PARAMETER_ELEMENT_NAME,a,instance).PointerValue,"First")==0,"dynamic label");
 GetParamEventsStruct events{0,nullptr};a.PointerValue=&events;require(entry(FF_GET_PARAMETER_EVENTS,a,instance).UIntValue==FF_SUCCESS && events.numEvents>0,"host refresh events");
 set(3,999);render();a.UIntValue=3;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==1,"sequence upper bound");set(4,-2);render();expected(4,8,0,0,0,32,32);
 // A second instance uses a different sequence and step from the same catalog.
 a.PointerValue=&vp;other=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(other && other!=(void*)(uintptr_t)FF_FAIL,"independent player");
 std::this_thread::sleep_for(std::chrono::milliseconds(100));void*first=instance;instance=other;set(2,1);set(5,1);render();set(3,0);set(4,1);render();expected(4,8,0,0,0,32,32);expected(44,40,0,0,0,32,32);instance=first;render();expected(4,8,0,0,0,32,32);sample(44,40,0,0,0);entry(FF_DEINSTANTIATE_GL,a,other);
 std::cout<<"PASS: dynamic catalog labels/events, stable IDs on reorder, bounds, simultaneous instances\n";
 for(int i=0;i<=1024;++i)curve[i]=@(1.0-i/1024.0);catalog[@"envelope"]=curve;writeCatalog();heartbeat(@"test-session");set(3,1);set(4,1);render();expected(44,40,0,0,0,32,32);sample(4,8,0,0,0);
 // Session mismatch and a stopped editor must pass through rather than play another project.
 heartbeat(@"other-session");render();expected(34,16,0,0,0,32,32);heartbeat(@"test-session");std::this_thread::sleep_for(std::chrono::milliseconds(1100));render();expected(34,16,0,0,0,32,32);
 heartbeat(@"test-session");render();std::this_thread::sleep_for(std::chrono::milliseconds(300));
 auto ack=[&](){NSData*d=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]];return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];};
 require(![ack()[@"resolutionMismatch"] boolValue],"logical input size ignores hardware texture padding");
 catalog[@"width"]=@128;writeCatalog();heartbeat(@"test-session");render();std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"resolutionMismatch"] boolValue],"resolution mismatch reported");
 // Invalid catalogs never replace the last usable project.
 catalog[@"sequences"]=@[@{@"id":@"bad",@"name":@"Broken",@"count":@2,@"bits":@"AQ==",@"durations":@[@1,@1]}];writeCatalog();heartbeat(@"test-session");render();a.UIntValue=3;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==1,"invalid bitset rejected");expected(44,40,0,0,0,32,32);
 for(int i=0;i<=1024;++i)curve[i]=@1;catalog[@"envelope"]=curve;catalog[@"sequences"]=@[seqA,seqB];writeCatalog();heartbeat(@"test-session");render();set(3,0);set(4,0);set(6,4);set(5,0);render();expected(4,8,0,0,0,32,32);sample(44,40,0,0,0);
 std::this_thread::sleep_for(std::chrono::milliseconds(180));set(2,1);set(3,0);set(4,0);set(5,0);set(6,4);render();expected(44,40,0,0,0,32,32);sample(4,8,0,0,0);
 set(5,1);set(4,0);render();std::this_thread::sleep_for(std::chrono::milliseconds(180));render();expected(4,8,0,0,0,32,32);sample(44,40,0,0,0);
 a.UIntValue=4;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_INTEGER,"Step integer metadata");require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"Step is an integer index");
 std::cout<<"PASS: automatic BPM advance with duration weights and explicit manual hold, integer Step\n";
 catalog[@"sequences"]=@[seqB];writeCatalog();heartbeat(@"test-session");render();a.UIntValue=3;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"removed selection falls back to first");
 heartbeat(@"test-session");render();std::this_thread::sleep_for(std::chrono::milliseconds(300));uint64_t beforeUploads=[ack()[@"gpuUploads"] unsignedLongLongValue];
 for(int i=0;i<20;++i)render();std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"gpuUploads"] unsignedLongLongValue]==beforeUploads,"unchanged geometry reuses GPU buffer");
 std::cout<<"PASS: removed-sequence fallback and no GPU uploads on 20 unchanged renders\n";
 set(2,0);render();expected(4,8,0,0,0,32,32);expected(44,40,0,0,0,32,32);
 std::cout<<"PASS: envelope sampling, session/stale safety, logical resolution warnings, invalid catalog and Editor fallback\n";

 // Named curves apply independently to each instance, including an editor-driven phase.
 NSMutableArray*low=[NSMutableArray array],*high=[NSMutableArray array];for(int i=0;i<=1024;++i){[low addObject:@0.25];[high addObject:@0.75];}
 NSDictionary*envA=@{@"id":@"envA",@"name":@"Soft",@"values":low},*envB=@{@"id":@"envB",@"name":@"Strong",@"values":high};
 catalog[@"envelopes"]=@[envA,envB];writeCatalog();
 auto envelopeFrame=[&](){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"session":@"test-session",@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@1,@"enabled":@YES,@"playing":@YES,@"phase":@0.5,@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"envelope frame");std::this_thread::sleep_for(std::chrono::milliseconds(70));};
 envelopeFrame();set(2,0);render();set(7,1);render();expected(4,8,0,0,0,32,32,.25);expected(44,40,0,0,0,32,32,.25);
 a.PointerValue=&vp;other=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(other && other!=(void*)(uintptr_t)FF_FAIL,"envelope second instance");std::this_thread::sleep_for(std::chrono::milliseconds(100));first=instance;instance=other;render();set(7,2);render();expected(4,8,0,0,0,32,32,.75);instance=first;render();expected(4,8,0,0,0,32,32,.25);
 catalog[@"envelopes"]=@[envB,envA];writeCatalog();envelopeFrame();render();a.UIntValue=7;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==2,"envelope UUID preserved on reorder");expected(4,8,0,0,0,32,32,.25);
 GetParameterElementNameStruct envelopeLabel{7,2};a.PointerValue=&envelopeLabel;require(strcmp((char*)entry(FF_GET_PARAMETER_ELEMENT_NAME,a,instance).PointerValue,"Soft")==0,"envelope names exposed");
 catalog[@"envelopes"]=@[envB];writeCatalog();envelopeFrame();render();a.UIntValue=7;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"deleted envelope falls back to project curve");expected(4,8,0,0,0,32,32);
 catalog[@"envelopes"]=@[envB,envB];writeCatalog();envelopeFrame();render();envelopeLabel={7,1};a.PointerValue=&envelopeLabel;require(strcmp((char*)entry(FF_GET_PARAMETER_ELEMENT_NAME,a,instance).PointerValue,"Strong")==0,"duplicate envelope IDs rejected without replacing catalog");
 entry(FF_DEINSTANTIATE_GL,a,other);
 std::cout<<"PASS: per-instance named envelopes, editor phase, alpha, dynamic labels, stable IDs, deletion fallback and malformed library rejection\n";

 for(int i=0;i<=1024;++i)curve[i]=@(1.0-i/1024.0);
 NSDictionary*echoSequence=@{@"id":@"echo-seq",@"name":@"Echo",@"count":@4,@"bits":@"AQIAAA==",@"durations":@[@1,@1,@1,@1]};
 catalog[@"sequences"]=@[echoSequence];catalog[@"envelope"]=curve;catalog[@"envelopes"]=@[];catalog[@"width"]=@64;writeCatalog();
 auto echoFrame=[&](double phase,bool playing){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"session":@"test-session",@"sequenceID":@"echo-seq",@"step":@1,@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(playing?1-phase:1),@"enabled":@YES,@"playing":@(playing),@"phase":@(phase),@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"echo frame");std::this_thread::sleep_for(std::chrono::milliseconds(70));};
 set(2,0);set(7,0);set(8,4);echoFrame(.5,true);
 for(int mode=0;mode<3;++mode){set(1,mode);render();expected(4,8,mode,0,0,32,32,.625);expected(44,40,mode,40,32,24,32,.875);}
 set(1,0);echoFrame(.25,true);render();std::this_thread::sleep_for(std::chrono::milliseconds(300));beforeUploads=[ack()[@"gpuUploads"] unsignedLongLongValue];
 echoFrame(.75,true);render();expected(4,8,0,0,0,32,32,.5625);expected(44,40,0,0,0,32,32,.8125);
 std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"gpuUploads"] unsignedLongLongValue]==beforeUploads,"echo fades reuse GPU vertices");
 echoFrame(.5,false);render();expected(4,8,0,0,0,32,32);expected(44,40,0,0,0,32,32);
 set(2,1);set(5,1);set(3,0);set(4,1);render();expected(4,8,0,0,0,32,32);expected(44,40,0,0,0,32,32);
 set(8,0);render();sample(4,8,0,0,0);expected(44,40,0,0,0,32,32);set(8,1);render();sample(4,8,0,0,0);
 set(8,4);set(4,1);set(6,1);set(5,0);echoFrame(.5,true);render();expected(4,8,0,0,0,32,32,.75);expected(44,40,0,0,0,32,32,1);
 a.UIntValue=8;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_INTEGER,"Echoes integer type");set(8,100);a.UIntValue=8;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==32,"echo upper bound");set(8,-1);a.UIntValue=8;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"echo lower bound");
 catalog[@"polygons"]=@[polygons[0],polygons[0]];writeCatalog();set(2,0);set(8,4);echoFrame(.5,true);
 glEnable(GL_BLEND);glBlendEquationSeparate(GL_FUNC_REVERSE_SUBTRACT,GL_FUNC_SUBTRACT);render();GLint eqRGB,eqAlpha;glGetIntegerv(GL_BLEND_EQUATION_RGB,&eqRGB);glGetIntegerv(GL_BLEND_EQUATION_ALPHA,&eqAlpha);
 require(glIsEnabled(GL_BLEND) && eqRGB==GL_FUNC_REVERSE_SUBTRACT && eqAlpha==GL_FUNC_SUBTRACT,"host blend equations restored");expected(4,8,0,0,0,32,32,.875);glDisable(GL_BLEND);glBlendEquation(GL_FUNC_ADD);
 for(int i=0;i<=1024;++i)curve[i]=@(i/1024.0);catalog[@"envelope"]=curve;writeCatalog();echoFrame(.5,true);render();expected(4,8,0,0,0,32,32,.375);
 std::cout<<"PASS: Echoes 0/1/4, independent fades, Editor/Arena/Manual/BPM, Mask/Fill/Stretch, overlap max, bounds, host blend state and GPU reuse\n";
 entry(FF_DEINSTANTIATE_GL,a,instance);a.PointerValue=nullptr;entry(FF_DEINITIALISE,a,nullptr);dlclose(lib);[[NSFileManager defaultManager]removeItemAtPath:dir error:nil];CGLSetCurrentContext(nullptr);CGLDestroyContext(ctx);
}}
