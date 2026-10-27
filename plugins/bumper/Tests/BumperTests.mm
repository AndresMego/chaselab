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
#include "../FFGL/BumperTiming.h"
static float asFloat(FFMixed m){float f;memcpy(&f,&m.UIntValue,sizeof(f));return f;}
#include <unistd.h>
static void require(bool v,const char* m){if(!v){std::cerr<<"FAIL: "<<m<<"\n";exit(1);}}
int main(int argc,char**argv){@autoreleasepool{
 require(argc==2,"plugin path");
 BumperTiming clock;clock.configure("A",3);clock.trigger(1,10);require(clock.cursor==0,"first Next uses first step");clock.trigger(1,10.1);require(clock.cursor==1,"Next advances");clock.trigger(-1,10.2);require(clock.cursor==0,"Previous reverses");clock.trigger(-1,10.3);require(clock.cursor==2,"Previous wraps");
 clock.idle(12,true,1.5);require(clock.cursor==-1,"inactivity rearms first step");clock.trigger(1,12.1);require(clock.cursor==0,"repeat begins from first");clock.idle(30,false,1.5);require(clock.cursor==0,"Auto Reset off preserves cursor");
 clock.configure("B",3);require(clock.voices.empty()&&clock.cursor==-1,"sequence change clears voices");clock.trigger(-1,31);require(clock.cursor==2,"initial Previous uses last");clock.clear();
 clock.tick(40,true,0,false,1.5);require(clock.cursor==0,"Blast press triggers immediately");clock.tick(40.5,true,0,false,1.5);require(clock.cursor==1,"Blast advances at 2 Hz");clock.tick(41,true,0,false,1.5);require(clock.cursor==2,"Blast repeats");clock.tick(41.1,false,0,false,1.5);clock.tick(42,false,0,false,1.5);require(clock.cursor==2,"Blast release stops advance");
 for(int i=0;i<1000;++i)clock.trigger(1,43+i*.001);require(clock.voices.size()<=3,"one bounded voice per step");clock.prune(50,1);require(clock.voices.empty(),"finished fades release voices");
 require(BumperTiming::fadeSeconds(1)<BumperTiming::fadeSeconds(0)&&BumperTiming::blastHz(1)>BumperTiming::blastHz(0),"higher speeds are faster");
 std::cout<<"PASS: Next/Previous wrap, first trigger, inactivity rearm, Auto Reset off, Blast hold/release, sequence reset and bounded voices\n";

 char temp[]="/private/tmp/chaselab-mapper-test.XXXXXX";require(mkdtemp(temp),"private directory");setenv("CHASELAB_BRIDGE_DIR",temp,1);NSString*dir=[NSString stringWithUTF8String:temp];
 CGLPixelFormatAttribute attrs[]={kCGLPFAOpenGLProfile,(CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,kCGLPFAAccelerated,(CGLPixelFormatAttribute)0};CGLPixelFormatObj fmt;GLint n;CGLContextObj ctx;require(CGLChoosePixelFormat(attrs,&fmt,&n)==kCGLNoError,"format");require(CGLCreateContext(fmt,nullptr,&ctx)==kCGLNoError,"context");CGLDestroyPixelFormat(fmt);CGLSetCurrentContext(ctx);
 void*lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!lib)std::cerr<<dlerror()<<"\n";require(lib,"dlopen");auto entry=(FF_Main_FuncPtr)dlsym(lib,"plugMain");require(entry,"entry");FFMixed a{};require(entry(FF_INITIALISE_V2,a,nullptr).UIntValue==FF_SUCCESS,"initialise");require(entry(FF_GET_NUM_PARAMETERS,a,nullptr).UIntValue==11,"eleven parameters");a.UIntValue=1;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_OPTION,"Scaling option");
 GLuint target,out,input;glGenTextures(1,&out);glBindTexture(GL_TEXTURE_2D,out);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,64,64,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glGenFramebuffers(1,&target);glBindFramebuffer(GL_FRAMEBUFFER,target);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,out,0);require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"FBO");
 std::vector<unsigned char> image(128*64*4,255);auto upload=[&](int alpha){for(int y=0;y<32;++y)for(int x=0;x<64;++x){int i=(y*128+x)*4;image[i]=std::lround(255.0*x/63);image[i+1]=std::lround(255.0*y/31);image[i+2]=32;image[i+3]=alpha;}glBindTexture(GL_TEXTURE_2D,input);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,128,64,0,GL_RGBA,GL_UNSIGNED_BYTE,image.data());glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glBindTexture(GL_TEXTURE_2D,0);};glGenTextures(1,&input);upload(255);
 FFGLTextureStruct texture{64,32,128,64,input};FFGLTextureStruct*ptr=&texture;ProcessOpenGLStruct process{1,&ptr,target};FFGLViewportStruct vp{0,0,64,64};a.PointerValue=&vp;void*instance=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(instance && instance!=(void*)(uintptr_t)FF_FAIL,"instantiate");
 auto set=[&](int index,float value){SetParameterStruct s{};s.ParameterNumber=index;memcpy(&s.NewParameterValue.UIntValue,&value,sizeof(value));a.PointerValue=&s;require(entry(FF_SET_PARAMETER,a,instance).UIntValue==FF_SUCCESS,"parameter");};
 int seq=0;NSArray*polygons=@[@[@[@-1,@-1],@[@0,@-1],@[@0,@0],@[@-1,@0]],@[@[@0.25,@0],@[@1,@0],@[@1,@1],@[@0.25,@1]]];
 auto write=[&](float intensity,bool enabled){NSDictionary*d=@{@"version":@1,@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@(intensity),@"enabled":@(enabled),@"polygons":polygons};NSData*data=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([data writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"fixture");std::this_thread::sleep_for(std::chrono::milliseconds(60));};
 auto render=[&](){glBindFramebuffer(GL_FRAMEBUFFER,target);glViewport(0,0,64,64);a.PointerValue=&process;require(entry(FF_PROCESS_OPENGL,a,instance).UIntValue==FF_SUCCESS,"render");glFinish();require(glGetError()==GL_NO_ERROR,"GL state/error");};
 auto sample=[&](int x,int y,int r,int g,int alpha){unsigned char p[4];glReadPixels(x,y,1,1,GL_RGBA,GL_UNSIGNED_BYTE,p);if(abs(p[0]-r)>3||abs(p[1]-g)>3||abs(p[3]-alpha)>3){std::cerr<<"at "<<x<<","<<y<<": "<<(int)p[0]<<","<<(int)p[1]<<","<<(int)p[3]<<" expected "<<r<<","<<g<<","<<alpha<<"\n";require(false,"pixel");}};
 auto expected=[&](int x,int y,int mode,double bx,double by,double bw,double bh,float level=1,int alpha=255){double u=(x+.5)/64,v=(y+.5)/64;if(mode){u=((x+.5)-bx)/bw;v=((y+.5)-by)/bh;if(mode==1){double aspect=bw/bh;if(2>aspect)u=(u-.5)*(aspect/2)+.5;else v=(v-.5)*(2/aspect)+.5;}}int sx=std::clamp((int)floor(u*64),0,63),sy=std::clamp((int)floor(v*32),0,31);sample(x,y,lround(lround(255.0*sx/63)*level),lround(lround(255.0*sy/31)*level),lround(alpha*level));};

 NSMutableArray*flat=[NSMutableArray array],*low=[NSMutableArray array];for(int i=0;i<=1024;++i){[flat addObject:@1];[low addObject:@0.25];}
 NSDictionary*seqA=@{@"id":@"A",@"name":@"First",@"count":@3,@"bits":@"AQIA",@"durations":@[@1,@1,@1]},*seqB=@{@"id":@"B",@"name":@"Second",@"count":@1,@"bits":@"Aw==",@"durations":@[@1]};
 NSMutableDictionary*catalog=[@{@"version":@1,@"session":@"bumper",@"width":@64,@"height":@32,@"polygons":polygons,@"sequences":@[seqA,seqB],@"envelope":flat,@"envelopes":@[@{@"id":@"soft",@"name":@"Soft",@"values":low}]}mutableCopy];
 auto writeCatalog=[&](){NSData*d=[NSJSONSerialization dataWithJSONObject:catalog options:0 error:nil];require([d writeToFile:[dir stringByAppendingPathComponent:@"catalog.json"] options:NSDataWritingAtomic error:nil],"catalog");std::this_thread::sleep_for(std::chrono::milliseconds(70));};
 auto heartbeat=[&](){NSDictionary*d=@{@"version":@1,@"session":@"bumper",@"sequence":@(++seq),@"time":@(NSDate.date.timeIntervalSince1970),@"intensity":@1,@"enabled":@YES,@"polygons":polygons};NSData*b=[NSJSONSerialization dataWithJSONObject:d options:0 error:nil];require([b writeToFile:[dir stringByAppendingPathComponent:@"frame.json"] options:NSDataWritingAtomic error:nil],"frame");std::this_thread::sleep_for(std::chrono::milliseconds(40));};
 auto tap=[&](int p){set(p,1);render();set(p,0);};
 writeCatalog();heartbeat();render();sample(4,8,0,0,0);sample(44,40,0,0,0);
 set(9,0);set(3,0);
 for(int mode=0;mode<3;++mode){set(1,mode);set(2,1);render();set(2,0);render();tap(5);expected(4,8,mode,0,0,32,32);sample(44,40,0,0,0);set(5,1);render();set(5,1);render();set(5,0);expected(44,40,mode,40,32,24,32);std::cout<<"PASS: Bumper scaling "<<mode<<" with per-trigger geometry and simultaneous fades\n";}
 set(1,0);set(2,1);render();set(2,0);render();set(5,1);render();set(5,0);render();sample(44,40,0,0,0);set(5,1);render();expected(4,8,0,0,0,32,32);expected(44,40,0,0,0,32,32);set(4,1);render();set(4,1);render();set(4,0);expected(4,8,0,0,0,32,32);
 a.UIntValue=5;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"Next is rearmed after rendering");a.UIntValue=4;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==0,"Previous is rearmed after rendering");
 set(2,1);render();set(2,0);render();set(5,1);set(5,1);render();expected(4,8,0,0,0,32,32);sample(44,40,0,0,0);render();sample(44,40,0,0,0);set(5,1);render();expected(44,40,0,0,0,32,32);
 set(2,1);render();set(2,0);render();set(8,1);tap(5);expected(4,8,0,0,0,32,32,.25);sample(44,40,0,0,0);
 auto ack=[&](){NSData*d=[NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"receiver.json"]];return [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];};
 std::this_thread::sleep_for(std::chrono::milliseconds(300));render();std::this_thread::sleep_for(std::chrono::milliseconds(300));auto before=[ack()[@"gpuUploads"] unsignedLongLongValue];for(int i=0;i<20;++i)render();std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"gpuUploads"] unsignedLongLongValue]==before,"stable fade reuses VBO");
 heartbeat();set(9,1);set(10,.1);std::this_thread::sleep_for(std::chrono::milliseconds(140));render();tap(5);a.UIntValue=5;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_EVENT,"Next event metadata");a.UIntValue=9;require(entry(FF_GET_PARAMETER_TYPE,a,nullptr).UIntValue==FF_TYPE_BOOLEAN,"Auto Reset boolean metadata");
 set(8,0);set(2,1);render();set(2,0);render();set(9,0);set(7,1);set(6,1);render();std::this_thread::sleep_for(std::chrono::milliseconds(40));render();set(6,0);std::this_thread::sleep_for(std::chrono::milliseconds(300));render();std::this_thread::sleep_for(std::chrono::milliseconds(300));int heldStep=[ack()[@"activeStep"] intValue];render();std::this_thread::sleep_for(std::chrono::milliseconds(300));require([ack()[@"activeStep"] intValue]==heldStep,"Blast release stops cursor");
 heartbeat();set(2,1);render();set(3,1);tap(5);std::this_thread::sleep_for(std::chrono::milliseconds(180));render();sample(4,8,0,0,0);sample(44,40,0,0,0);
 NSMutableArray*fallCurve=[NSMutableArray array];for(int i=0;i<=1024;++i)[fallCurve addObject:@(1.0-i/1024.0)];catalog[@"envelope"]=fallCurve;writeCatalog();heartbeat();set(2,0);render();set(3,0);tap(5);unsigned char startPixel[4],endPixel[4];glReadPixels(4,8,1,1,GL_RGBA,GL_UNSIGNED_BYTE,startPixel);std::this_thread::sleep_for(std::chrono::milliseconds(160));render();glReadPixels(4,8,1,1,GL_RGBA,GL_UNSIGNED_BYTE,endPixel);require(endPixel[3]>0&&endPixel[3]<startPixel[3],"actual RGB/alpha fade progresses before expiry");
 set(0,0);render();expected(34,16,0,0,0,32,32);set(0,1);std::this_thread::sleep_for(std::chrono::milliseconds(1100));render();expected(34,16,0,0,0,32,32);
 heartbeat();render();sample(4,8,0,0,0);tap(5);render();expected(4,8,0,0,0,32,32);
 catalog[@"sequences"]=@[seqB,seqA];writeCatalog();heartbeat();render();a.UIntValue=2;require(asFloat(entry(FF_GET_PARAMETER,a,instance))==1,"sequence UUID preserved after reorder");
 a.PointerValue=&vp;void*other=entry(FF_INSTANTIATE_GL,a,nullptr).PointerValue;require(other&&other!=(void*)(uintptr_t)FF_FAIL,"second instance");std::this_thread::sleep_for(std::chrono::milliseconds(70));void*first=instance;instance=other;render();sample(4,8,0,0,0);sample(44,40,0,0,0);set(1,0);tap(5);expected(44,40,0,0,0,32,32);instance=first;
 entry(FF_DEINSTANTIATE_GL,a,other);entry(FF_DEINSTANTIATE_GL,a,instance);a.PointerValue=nullptr;entry(FF_DEINITIALISE,a,nullptr);dlclose(lib);[[NSFileManager defaultManager]removeItemAtPath:dir error:nil];CGLSetCurrentContext(nullptr);CGLDestroyContext(ctx);
 std::cout<<"PASS: repeated positive triggers without release, consumed button state, named envelope, VBO reuse, Auto Reset controls, Blast release, fade expiry, Amount, stale reconnect, stable sequence UUID and independent instances\n";
}}
