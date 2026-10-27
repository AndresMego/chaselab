// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 ChaseLab contributors
#pragma once
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstdint>

// -1 is inactive; zero remains in the geometry so curve animation never uploads vertices.
static std::vector<float> echoLevels(const std::vector<double>& durations,const std::vector<uint8_t>& bits,
                                    size_t rows,int index,double phase,int echoes,bool hold,
                                    const std::vector<float>& curve) {
    const int count=(int)durations.size(),span=std::clamp(echoes,1,32);
    std::vector<float> levels(rows,-1);
    if(count<1 || index<0 || index>=count || curve.size()!=1025 || bits.size()!=count*((rows+7)/8))return levels;
    const size_t stride=(rows+7)/8;
    double age=std::clamp(phase,0.0,1.0)*durations[index];
    for(int k=0;k<span;++k) {
        const int trigger=(index-k%count+count)%count;
        if(k>0)age+=durations[trigger];
        double lifetime=0;
        for(int j=0;j<span;++j)lifetime+=durations[(trigger+j)%count];
        const double sample=std::clamp(age/lifetime,0.0,1.0)*1024;
        const int base=std::min(1023,(int)sample);
        const float intensity=hold?1:curve[base]+(curve[base+1]-curve[base])*(sample-base);
        for(size_t r=0;r<rows;++r)if(bits[trigger*stride+r/8] & (1<<(r%8)))levels[r]=std::max(levels[r],intensity);
    }
    return levels;
}
