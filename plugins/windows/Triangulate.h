// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <vector>
#include <cmath>
#include <algorithm>
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
