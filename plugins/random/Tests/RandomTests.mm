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
#include <fstream>

static float asFloat(FFMixed m){float f;memcpy(&f,&m.UIntValue,sizeof(f));return f;}
#include <unistd.h>
static void require(bool v,const char* m){if(!v){std::cerr<<"FAIL: "<<m<<"\n";exit(1);}}
int main(int argc,char**argv){@autoreleasepool{
 require(argc==2,"plugin path and source mode");bool source=false;
 char temp[]="/private/tmp/chaselab-mapper-test.XXXXXX";require(mkdtemp(temp),"private directory");setenv("CHASELAB_BRIDGE_DIR",temp,1);NSString*dir=[NSString stringWithUTF8String:temp];
 CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};CGLPixelFormatObj fmt;GLint n;CGLContextObj ctx;require(CGLChoosePixelFormat(attrs,&fmt,&n)==kCGLNoError,"format");require(CGLCreateContext(fmt,nullptr,&ctx)==kCGLNoError,"context");CGLDestroyPixelFormat(fmt);CGLSetCurrentContext(ctx);
 void*lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!lib)std::cerr<<dlerror()<<"\n";require(lib,"dlopen");auto entry=(FF_Main_FuncPtr)dlsym(lib,"plugMain");require(entry,"entry");FFMixed a{};require(entry(FF_INITIALISE_V2,a,nullptr).UIntValue==FF_SUCCESS,"initialise");require(entry(FF_GET_NUM_PARAMETERS,a,nullptr).UIntValue==10,"ten parameters");a.UIntValue=0;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_OPTION,"Scaling option");
 GLuint target,out,input;glGenTextures(1,&out);glBindTexture(GL_TEXTURE_2D,out);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glGenFramebuffers(1,&target);glBindFramebuffer(GL_FRAMEBUFFER,target);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,out,0);require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"FBO");
 std::vector<unsigned char> image(128*64*4,255);auto upload=[&](int alpha){for(int y=0;y<32;++y)for(int x=0;x<64;++x){int i=(y*128+x)*4;image[i]=std::lround(255.0*x/63);image[i+1]=std::lround(255.0*y/31);image[i+2]=32;image[i+3]=alpha;}glBindTexture(GL_TEXTURE_2D,input);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,128,64,0,GL_RGBA,GL_UNSIGNED_BYTE,image.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glBindTexture(GL_TEXTURE_2D,0);};glGenTextures(1,&input);upload(255);
 FFGLTextureStruct texture{64,32,128,64,input};FFGLTextureStruct*ptr=&texture;ProcessOpenGLStruct process{source?0u:1u,source?nullptr:&ptr,target};FFGLViewportStruct vp{0,0,64,64};a.PointerValue=&vp;void*instance=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(instance && instance!=(void*)(uintptr_t)FF_FAIL,"instantiate");
 auto set=[&](int index,float value){SetParameterStruct s{};s.ParameterNumber=index;memcpy(&s.NewParameterValue.UIntValue,&value,sizeof(value));a.PointerValue=&s;require(entry(FF_SET_PARAMETER,a,instance).UIntValue==FF_SUCCESS,"parameter");};
 int seq=0;NSArray*polygons=@[@[@[@-1,@-1],@[@0,@-1],@[@0,@0],@[@-1,@0]],@[@[@0.25,@0],@[@1,@0],@[@1,@1],@[@0.25,@1]]];
 auto write=[&](float intensity,bool enabled){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(intensity),@"enabled":@(enabled),@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"fixture");std::this_thread::sleep_for(std::chrono::milliseconds(60));};
 auto render=[&](){glBindFramebuffer(GL_FRAMEBUFFER,target);glViewport(0,0,64,64);a.PointerValue=&process;require(entry(FF_PROCESS_OPENGL,a,instance).UIntValue==FF_SUCCESS,"render");glFinish();require(glGetError()==GL_NO_ERROR,"GL state/error");};
 auto sample=[&](int x,int y,int r,int g,int alpha){unsigned char p[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,p);if(abs(p[0]-r)>3||abs(p[1]-g)>3||abs(p[3]-alpha)>3){std::cerr<<"at "<<x<<","<<y<<": "<<(int)p[0]<<","<<(int)p[1]<<","<<(int)p[3]<<" expected "<<r<<","<<g<<","<<alpha<<"\n";require(false,"pixel");}};
 auto expected=[&](int x,int y,int mode,double bx,double by,double bw,double bh,float level=1,int alpha=255){double u=(x+.5)/64,v=(y+.5)/64;if(mode){u=((x+.5)-bx)/bw;v=((y+.5)-by)/bh;if(mode==1){double aspect=bw/bh;if(2>aspect)u=(u-.5)*(aspect/2)+.5;else v=(v-.5)*(2/aspect)+.5;}}int sx=std::clamp((int)floor(u*64),0,63),sy=std::clamp((int)floor(v*32),0,31);sample(x,y,lround(lround(255.0*sx/63)*level),lround(lround(255.0*sy/31)*level),lround(alpha*level));};


 NSMutableArray*flat=[NSMutableArray array],*low=[NSMutableArray array];for(int i=0;i<=1024;++i){[flat addObject:@1];[low addObject:@0.25];}
 NSDictionary*seqA=@{@"id":@"A",@"name":@"First",@"count":@1,@"bits":@"Aw==",@"durations":@[@1]};
 NSMutableDictionary*catalog=[@{@"version":@1,@"session":@"outliner",@"width":@64,@"height":@(source?64:32),@"polygons":polygons,@"sequences":@[seqA],@"envelope":flat,@"envelopes":@[@{@"id":@"soft",@"name":@"Soft",@"values":low}]}mutableCopy];
 auto writeCatalog=[&](){NSData*d=[NSJSONSerialization dataWithJSONObject:catalog options:0 error:nil];require([d writeToFile:[dir stringByAppendingPathComponent:@"catalog.json"] options:NSDataWritingAtomic error:nil],"catalog");std::this_thread::sleep_for(std::chrono::milliseconds(80));};
 auto heartbeat=[&](){NSDictionary*d=@{@"version":@1,@"session":@"outliner",@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@1,@"enabled":@YES,@"polygons":polygons};NSData*b=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([b writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"frame");std::this_thread::sleep_for(std::chrono::milliseconds(40));};
 auto alpha=[&](int x,int y){unsigned char p[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,p);return(int)p[3];};
 auto hash=[&](){std::vector<unsigned char>px(64*64*4);glReadPixels(0,0,64,64,GL_RGBA,GL_UNSIGNED_BYTE,px.data());uint64_t value=1469598103934665603ull;for(auto x:px)value=(value^x)*1099511628211ull;return value;};

 writeCatalog();heartbeat();set(2,1);set(0,0);set(5,0);render();sample(16,16,0,0,0);sample(48,48,0,0,0);
 set(4,1);render();bool first=alpha(16,16)>200;require(first!=(alpha(48,48)>200),"one random selection lights one of two slices");int x=first?16:48,y=first?16:48;expected(x,y,0,first?0:40,first?0:32,first?32:24,32);sample(34,16,0,0,0);
 set(0,1);render();expected(x,y,1,first?0:40,first?0:32,first?32:24,32);set(0,2);render();expected(x,y,2,first?0:40,first?0:32,first?32:24,32);set(0,0);set(8,1);render();expected(x,y,0,0,0,32,32,.25);
 catalog[@"envelopes"]=@[@{@"id":@"full",@"name":@"Full",@"values":flat},@{@"id":@"soft",@"name":@"Renamed",@"values":low}];writeCatalog();heartbeat();render();a.UIntValue=8;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==2,"Envelope identity survives reorder");expected(x,y,0,0,0,32,32,.25);set(8,0);
 glEnable(GL_CULL_FACE);glEnable(GL_DEPTH_TEST);glEnable(GL_SCISSOR_TEST);glScissor(0,0,0,0);glEnable(GL_STENCIL_TEST);glColorMask(GL_FALSE,GL_FALSE,GL_FALSE,GL_FALSE);render();expected(x,y,0,0,0,32,32);GLboolean masks[4];glGetBooleanv(GL_COLOR_WRITEMASK,masks);require(glIsEnabled(GL_CULL_FACE)&&glIsEnabled(GL_DEPTH_TEST)&&glIsEnabled(GL_SCISSOR_TEST)&&glIsEnabled(GL_STENCIL_TEST)&&!masks[0]&&!masks[3],"host states restored");glDisable(GL_CULL_FACE);glDisable(GL_DEPTH_TEST);glDisable(GL_SCISSOR_TEST);glDisable(GL_STENCIL_TEST);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);
 auto ack=[&](){NSData*d=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]];return d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;};
 std::this_thread::sleep_for(std::chrono::milliseconds(300));render();std::this_thread::sleep_for(std::chrono::milliseconds(300));auto uploads=[ack()[@"gpuUploads"] unsignedLongLongValue];heartbeat();for(int i=0;i<20;++i){set(9,i/20.f);set(7,i);render();}std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"gpuUploads"] unsignedLongLongValue]==uploads,"parameter changes reuse GPU geometry");set(9,1);set(7,0);
 heartbeat();a.UIntValue=4;require(entry(FF_GET_PRAMETER_VISIBILITY,a,instance).UIntValue==1,"Manual shows Next");a.UIntValue=7;require(entry(FF_GET_PRAMETER_VISIBILITY,a,instance).UIntValue==0,"Manual hides Echoes");
 auto generation=[ack()[@"generation"] unsignedLongLongValue];for(int i=0;i<5;++i){heartbeat();set(4,1);render();a.UIntValue=4;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"Next rearmed after render");std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"generation"] unsignedLongLongValue]==++generation,"consecutive Next generates one new selection");}
 set(6,7);a.UIntValue=6;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==1,"Max Slices clamped to row limit");
 set(2,0);set(3,1);heartbeat();render();std::this_thread::sleep_for(std::chrono::milliseconds(300));auto start=[ack()[@"generation"] unsignedLongLongValue];heartbeat();render();std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"generation"] unsignedLongLongValue]>start,"automatic random generation advances");
 set(9,0);render();expected(34,16,0,0,0,32,32);set(9,1);
 std::this_thread::sleep_for(std::chrono::milliseconds(1100));render();expected(34,16,0,0,0,32,32);heartbeat();render();sample(34,16,0,0,0);
 NSData*bad=[NSJSONSerialization dataWithJSONObject:@{@"version":[NSNull null],@"enabled":[NSNull null]} options:0 error:nil];[bad writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil];std::this_thread::sleep_for(std::chrono::milliseconds(70));render();expected(34,16,0,0,0,32,32);heartbeat();render();sample(34,16,0,0,0);
 catalog[@"polygons"]=@[@[@[@-1,@-1],@[@1,@-1],@[@1,@0],@[@0,@0],@[@0,@1],@[@-1,@1]]];catalog[@"sequences"]=@[@{@"id":@"A",@"name":@"First",@"count":@1,@"bits":@"AQ==",@"durations":@[@1]}];writeCatalog();heartbeat();set(2,1);set(5,0);set(4,1);render();expected(16,48,0,0,0,32,32);sample(48,48,0,0,0);
 std::cout<<"PASS: random selection pixels, Mask/Fill/Stretch, named envelope identity, host-state restore, geometry reuse, five consecutive Next, dynamic slice cap, Auto progression, Amount, stale/malformed safety, concave clipping\n";
 entry(FF_DEINSTANTIATE_GL,a,instance);a.PointerValue=nullptr;entry(FF_DEINITIALISE,a,nullptr);dlclose(lib);[[NSFileManager defaultManager]removeItemAtPath:dir error:nil];CGLSetCurrentContext(nullptr);CGLDestroyContext(ctx);
}}
