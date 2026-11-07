// SPDX-License-Identifier: Apache-2.0
#include <windows.h>
#include <FFGLSDK.h>
#include <ffglex/FFGLScopedFBOBinding.h>
#include <nlohmann/json.hpp>
#include <filesystem>
#include <fstream>
#include <thread>
#include <atomic>
#include <mutex>
#include <chrono>
#include "Triangulate.h"
using json=nlohmann::json;
using namespace ffglex;
static double epoch(){return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();}
struct Frame{std::vector<P> vertices;double time=0,width=0,height=0;float level=1;bool enabled=false;};
class Player:public CFFGLPlugin {
 FFGLShader shader;FFGLScreenQuad quad;GLuint vao=0,vbo=0;std::thread reader;std::atomic<bool> run{false};std::mutex mutex;Frame pending,current;std::atomic<float>bpm{0};std::atomic<int>width{0},height{0};std::filesystem::path dir;float level=1;std::vector<P>uploaded;
 void read(){while(run){try{
  auto path=dir/L"frame.json";
  if(std::filesystem::exists(path)&&std::filesystem::file_size(path)<2'000'000){std::ifstream stream(path);auto j=json::parse(stream);Frame next;next.time=j.at("time").get<double>();next.width=j.at("width").get<double>();next.height=j.at("height").get<double>();next.level=j.at("intensity").get<float>();next.enabled=j.at("enabled").get<bool>();auto &polys=j.at("polygons");
   if(j.at("version")!=1||!std::isfinite(next.time)||!std::isfinite(next.level)||next.level<0||next.level>1||!std::isfinite(next.width)||!std::isfinite(next.height)||next.width<1||next.height<1||next.width>16384||next.height>16384||!polys.is_array()||polys.size()>256)throw std::runtime_error("Invalid frame");
   size_t count=0;for(auto &poly:polys){if(!poly.is_array()||poly.size()<3||poly.size()>1024)throw std::runtime_error("Invalid polygon");count+=poly.size();if(count>16384)throw std::runtime_error("Too many vertices");std::vector<P> points;for(auto &p:poly){if(!p.is_array()||p.size()!=2)throw std::runtime_error("Invalid point");P point{p[0].get<float>(),p[1].get<float>()};if(!std::isfinite(point.x)||!std::isfinite(point.y)||std::abs(point.x)>1e6||std::abs(point.y)>1e6)throw std::runtime_error("Invalid coordinates");points.push_back(point);}if(!triangulate(points,next.vertices))throw std::runtime_error("Cannot triangulate polygon");}
   std::lock_guard<std::mutex>lock(mutex);pending=std::move(next);
  }
  if(width.load()>0){std::filesystem::create_directories(dir);json ack={{"time",epoch()},{"bpm",bpm.load()},{"width",width.load()},{"height",height.load()},{"effect","windows-demo"}};auto temp=dir/(L"receiver-"+std::to_wstring(reinterpret_cast<uintptr_t>(this))+L".tmp");{std::ofstream out(temp);out<<ack.dump();}MoveFileExW(temp.c_str(),(dir/L"receiver.json").c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH);}
 }catch(const std::exception&){}std::this_thread::sleep_for(std::chrono::milliseconds(33));}}
public:
 Player(){SetMinInputs(1);SetMaxInputs(1);SetParamInfo(0,"Level",FF_TYPE_STANDARD,1.f);}
 ~Player()override{run=false;if(reader.joinable())reader.join();}
 FFResult SetFloatParameter(unsigned i,float v)override{if(i||!std::isfinite(v))return FF_FAIL;level=std::clamp(v,0.f,1.f);return FF_SUCCESS;}
 float GetFloatParameter(unsigned i)override{return i==0?level:0;}
 void SetBeatInfo(float b,float p)override{CFFGLPlugin::SetBeatInfo(b,p);if(std::isfinite(b)&&b>=20&&b<=300)bpm=b;}
 FFResult InitGL(const FFGLViewportStruct*vp)override{
  glewExperimental=GL_TRUE;if(glewInit()!=GLEW_OK)return FF_FAIL;while(glGetError()!=GL_NO_ERROR){}
  const char*vs="#version 330 core\nlayout(location=0)in vec4 vertex;layout(location=1)in vec2 texcoord;uniform bool mesh;out vec2 uv;void main(){gl_Position=vec4(vertex.xy,0,1);uv=mesh?(vertex.xy+1.)*.5:texcoord;}";
  const char*fs="#version 330 core\nuniform sampler2D image;uniform vec2 extent;uniform float level;in vec2 uv;out vec4 color;void main(){color=texture(image,uv*extent)*level;}";
  if(!shader.Compile(vs,fs)||!quad.Initialise())return FF_FAIL;
  GLint oldVao,oldBuffer;glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&oldVao);glGetIntegerv(GL_ARRAY_BUFFER_BINDING,&oldBuffer);glGenVertexArrays(1,&vao);glGenBuffers(1,&vbo);glBindVertexArray(vao);glBindBuffer(GL_ARRAY_BUFFER,vbo);glEnableVertexAttribArray(0);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,sizeof(P),nullptr);glBindVertexArray(oldVao);glBindBuffer(GL_ARRAY_BUFFER,oldBuffer);
  wchar_t*local=nullptr;size_t length=0;_wdupenv_s(&local,&length,L"LOCALAPPDATA");if(!local)return FF_FAIL;dir=std::filesystem::path(local)/L"ChaseLab_MM"/L"bridge-win-demo";free(local);run=true;try{reader=std::thread(&Player::read,this);}catch(...){run=false;return FF_FAIL;}return CFFGLPlugin::InitGL(vp);
 }
 FFResult DeInitGL()override{run=false;if(reader.joinable())reader.join();if(vbo)glDeleteBuffers(1,&vbo);if(vao)glDeleteVertexArrays(1,&vao);vao=vbo=0;shader.FreeGLResources();quad.Release();return FF_SUCCESS;}
 FFResult ProcessOpenGL(ProcessOpenGLStruct*p)override{
  if(!p||p->numInputTextures<1||!p->inputTextures[0])return FF_FAIL;auto input=p->inputTextures[0];width=input->Width;height=input->Height;{std::unique_lock<std::mutex>lock(mutex,std::try_to_lock);if(lock.owns_lock())current=pending;}
  bool live=current.enabled&&epoch()-current.time<1&&epoch()-current.time>=-.1;
  const GLenum caps[]={GL_BLEND,GL_DEPTH_TEST,GL_CULL_FACE,GL_SCISSOR_TEST,GL_STENCIL_TEST};GLboolean saved[5],mask[4];for(int i=0;i<5;i++){saved[i]=glIsEnabled(caps[i]);glDisable(caps[i]);}glGetBooleanv(GL_COLOR_WRITEMASK,mask);glColorMask(GL_TRUE,GL_TRUE,GL_TRUE,GL_TRUE);GLfloat clear[4];glGetFloatv(GL_COLOR_CLEAR_VALUE,clear);GLint oldVao,oldBuffer;glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&oldVao);glGetIntegerv(GL_ARRAY_BUFFER_BINDING,&oldBuffer);
  {ScopedFBOBinding target(p->HostFBO,ScopedFBOBinding::RB_REVERT);ScopedShaderBinding program(shader.GetGLID());ScopedSamplerActivation sampler(0);Scoped2DTextureBinding texture(input->Handle);glUniform1i(shader.FindUniform("image"),0);shader.Set("extent",float(input->Width)/input->HardwareWidth,float(input->Height)/input->HardwareHeight);glUniform1f(shader.FindUniform("level"),live?current.level*level:1);glUniform1i(shader.FindUniform("mesh"),live?1:0);
   if(live){glClearColor(0,0,0,0);glClear(GL_COLOR_BUFFER_BIT);glBindVertexArray(vao);glBindBuffer(GL_ARRAY_BUFFER,vbo);if(uploaded.size()!=current.vertices.size()||!std::equal(uploaded.begin(),uploaded.end(),current.vertices.begin(),[](P a,P b){return a.x==b.x&&a.y==b.y;})){glBufferData(GL_ARRAY_BUFFER,current.vertices.size()*sizeof(P),current.vertices.data(),GL_DYNAMIC_DRAW);uploaded=current.vertices;}glDrawArrays(GL_TRIANGLES,0,GLsizei(current.vertices.size()));}else quad.Draw();
  }
  glBindVertexArray(oldVao);glBindBuffer(GL_ARRAY_BUFFER,oldBuffer);glClearColor(clear[0],clear[1],clear[2],clear[3]);glColorMask(mask[0],mask[1],mask[2],mask[3]);for(int i=0;i<5;i++)if(saved[i])glEnable(caps[i]);return FF_SUCCESS;
 }
};
static CFFGLPluginInfo info(PluginFactory<Player>,"CW01","CL Win Demo_MM",2,1,0,1,FF_EFFECT,"Experimental Windows editor-controlled slice mask","Apache-2.0 ChaseLab contributors");
