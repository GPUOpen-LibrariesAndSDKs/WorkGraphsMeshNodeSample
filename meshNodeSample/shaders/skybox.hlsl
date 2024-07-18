// This file is part of the AMD Work Graph Mesh Node Sample.
//
// Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#pragma once

#include "shadingcommon.h"
#include "utils.hlsl"

// namespace contains skybox lookup gradients based on the lookup textures from https://kelvinvanhoorn.com/2022/03/17/skybox-tutorial-part-1/
namespace skybox {


    float SunZenith_Gradient_b(float x)
    {
        const int   count = 5;
        const float xs[count] = { 0.0, 0.375, 0.515625, 0.625, 0.9921875 };
        const float ys[count] = {
            0.09119905696129081, 0.17743197428764693, 0.5457624421381186, 0.8458267513775317, 0.8470588235294116 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float SunZenith_Gradient_g(float x)
    {
        const int   count = 4;
        const float xs[count] = { 0.0, 0.3828125, 0.6171875, 0.9921875 };
        const float ys[count] = { 0.055852483484183674, 0.1324827899848155, 0.678304263482747, 0.5670582583360976 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float SunZenith_Gradient_r(float x)
    {
        const int   count = 4;
        const float xs[count] = { 0.0, 0.375, 0.6171875, 0.9921875 };
        const float ys[count] = { 0.05266772050977707, 0.0846283802271616, 0.37306694022972375, 0.2979585185575305 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float3 SunZenith_Gradient(float x)
    {
        return float3(SunZenith_Gradient_r(x), SunZenith_Gradient_g(x), SunZenith_Gradient_b(x));
    }

    float ViewZenith_Gradient_b(float x)
    {
        const int   count = 6;
        const float xs[count] = { 0.0, 0.375, 0.484375, 0.5390625, 0.6484375, 0.9921875 };
        const float ys[count] = { 0.020563663948531673,
                                 0.3419597608904451,
                                 0.04161602600815216,
                                 0.1095349428231567,
                                 0.8149446289251109,
                                 0.9900099167444902 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float ViewZenith_Gradient_g(float x)
    {
        const int   count = 5;
        const float xs[count] = { 0.0, 0.359375, 0.53125, 0.6171875, 0.9921875 };
        const float ys[count] = {
            0.010815067628993518, 0.19845916353774884, 0.5742594966049783, 0.7342900528103369, 0.748949825687303 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float ViewZenith_Gradient_r(float x)
    {
        const int   count = 6;
        const float xs[count] = { 0.0, 0.359375, 0.4921875, 0.59375, 0.640625, 0.9921875 };
        const float ys[count] = { 0.009057957120245073,
                                 0.15106019459324935,
                                 0.9180293234405212,
                                 0.47611197653854354,
                                 0.5406124274378104,
                                 0.500948270549165 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float3 ViewZenith_Gradient(float x)
    {
        return float3(ViewZenith_Gradient_r(x), ViewZenith_Gradient_g(x), ViewZenith_Gradient_b(x));
    }

    float SunView_Gradient_b(float x)
    {
        const int   count = 5;
        const float xs[count] = { 0.0, 0.4765625, 0.6328125, 0.984375, 0.9921875 };
        const float ys[count] = {
            0.0, 0.025240814536934993, 0.35683113031269376, 0.6095478205423517, 0.6113290117056305 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float SunView_Gradient_g(float x)
    {
        const int   count = 5;
        const float xs[count] = { 0.0, 0.3828125, 0.515625, 0.6171875, 0.9921875 };
        const float ys[count] = {
            0.0038584077592145796, 0.11097681754988054, 0.7754699617187375, 0.5145669601324688, 0.6615264387746628 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float SunView_Gradient_r(float x)
    {
        const int   count = 5;
        const float xs[count] = { 0.0, 0.3828125, 0.515625, 0.6328125, 0.9921875 };
        const float ys[count] = {
            0.005119371666456357, 0.147390195920971, 0.9702326103489829, 0.26112308728542827, 0.39095905970609257 };
        for (int i = 0; i < (count - 1); ++i) {
            if (xs[i] <= x && x < xs[i + 1]) {
                float t = (x - xs[i]) / (xs[i + 1] - xs[i]);
                return lerp(ys[i], ys[i + 1], smoothstep(0., 1., t));
            }
        }
        return ys[count - 1];
    }

    float3 SunView_Gradient(float x)
    {
        return float3(SunView_Gradient_r(x), SunView_Gradient_g(x), SunView_Gradient_b(x));
    }

}  // namespace skybox

struct LightingData {
    float3 sunDirection;
    float3 moonDirection;

    float3 globalLightDirection;
};

LightingData GetLightingData()
{
    LightingData result;

    const float southAngle = ToRadians(0.0);
    const float latitude   = ToRadians(0.0);
    const float timeOfDay  = 12.0;

    const float3 up    = float3(0, 1, 0);
    const float3 south = float3(cos(southAngle), 0, sin(southAngle));

    const float3 right = normalize(cross(south, up));

    const float sunAngle = (timeOfDay / 24.f) * 2 * PI;

    const float3 sunVector = -cos(sunAngle) * up + -sin(sunAngle) * right;
    result.sunDirection = normalize(cos(latitude) * sunVector + sin(latitude) * south);
    result.moonDirection = normalize(cos(latitude) * -sunVector + sin(latitude) * -south);

    result.globalLightDirection = (result.sunDirection.y < 0) ? result.moonDirection : result.sunDirection;

    return result;
}

// Skybox based on https://kelvinvanhoorn.com/2022/03/17/skybox-tutorial-part-1/
float3 GetSkyboxColor(in float3 direction, in LightingData lightingData)
{
    const float sunViewDot    = dot(lightingData.sunDirection, direction);
    const float moonViewDot   = dot(lightingData.moonDirection, direction);
    const float sunZenithDot  = lightingData.sunDirection.y;
    const float viewZenithDot = direction.y;
    const float sunMoonDot    = dot(lightingData.sunDirection, lightingData.moonDirection);

    float sunViewDot01   = (sunViewDot + 1.0) * 0.5;
    float sunZenithDot01 = (sunZenithDot + 1.0) * 0.5;

    float3 sunZenithColor = skybox::SunZenith_Gradient(sunZenithDot01);

    float3 viewZenithColor = skybox::ViewZenith_Gradient(sunZenithDot01) ;
    float  vzMask          = pow(saturate(1.0 - viewZenithDot), 4);

    float3 sunViewColor = skybox::SunView_Gradient(sunZenithDot01) * 0.7;
    float  svMask       = pow(saturate(sunViewDot), 4);

    float3 skyColor = sunZenithColor + vzMask * viewZenithColor + svMask * sunViewColor;

    const float sunRadius  = 0.05;
    const float sunMask    = step(1 - (sunRadius * sunRadius), sunViewDot);
    const float sunVisible = clamp((lightingData.sunDirection.y + 5 * sunRadius) / (5 * sunRadius), 0, 1);

    const float3 sunColor = sunMask * sunVisible;

    const float moonRadius  = 0.03;
    const float moonMask    = step(1 - (moonRadius * moonRadius), moonViewDot);
    const float moonVisible = clamp((lightingData.moonDirection.y + 5 * moonRadius) / (5 * moonRadius), 0, 1);

    const float3 moonColor =  moonMask * moonVisible;

    return skyColor + sunColor + moonColor;
}