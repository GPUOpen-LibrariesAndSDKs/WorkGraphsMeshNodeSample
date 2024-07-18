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

#include "common.hlsl"

struct ShroomType {
    int hatPoints;
    int stemPoints;

    float hatRingInnerRadius;
    float hatRingOuterRadius;
    float stemRingRadius;

    float hatRingInnerDepth;
    float hatRingOuterDepth;

    float hatTilt;
    float shroomCountBiasPow;
    float positionNoise;

    float3 stemColor;
    float3 hatColor;
};

// Mushroom definitions
static const int        numShroomTypes              = 2;
static const ShroomType shroomTypes[numShroomTypes] = {  //
    {
        // brown shroom
        7,                              // int hatPoints;
        5,                              // int stemPoints;
        .25,                            // float hatRingInnerRadius;
        .4,                             // float hatRingOuterRadius;
        .1,                             // float stemRingRadius;
        .075,                           // float hatRingInnerDepth;
        .25,                            // float hatRingOuterDepth;
        .65,                            // float hatTilt;
        1,                              // float shroomCountBiasPow;
        .025,                           // float positionNoise;
        float3(0.33, 0.21, 0.14) * .8,  // float3 stemColor
        float3(0.33, 0.21, 0.14) * .8   // float3 hatColor
    },
    {
        // red shroom
        8,                           // int hatPoints;
        5,                           // int stemPoints;
        .25,                         // float hatRingInnerRadius;
        .4,                          // float hatRingOuterRadius;
        .1,                          // float stemRingRadius;
        .05,                         // float hatRingInnerDepth;
        .15,                         // float hatRingOuterDepth;
        .1,                          // float hatTilt;
        1,                           // float shroomCountBiasPow;
        .025,                        // float positionNoise;
        float3(1, 1, 1) * .6,        // float3 stemColor
        float3(.225, 0.05, 0.) * .5  // float3 hatColor
    },
};

static const float radiusMin = 0.2;
static const float radiusV   = 0.2;
static const float scale     = .6;

static const int mushroomGroupSize       = 128;
static const int numOutputVerticesLimit  = 256;
static const int numOutputTrianglesLimit = 192;

static const int numOutputVertexIterations   = (numOutputVerticesLimit + (mushroomGroupSize - 1)) / mushroomGroupSize;
static const int numOutputTriangleIterations = (numOutputTrianglesLimit + (mushroomGroupSize - 1)) / mushroomGroupSize;

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawMushroomPatch", 0)]
[NodeMaxDispatchGrid(maxMushroomsPerRecord, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(50, true)]
[NumThreads(mushroomGroupSize, 1, 1)]
[OutputTopology("triangle")]
void MushroomMeshShader(
    uint                                        gtid : SV_GroupThreadID,
    uint                                        gid : SV_GroupID,
    DispatchNodeInputRecord<DrawMushroomRecord> inputRecord,
    out indices uint3                           tris[numOutputTrianglesLimit],
    out vertices InsectVertex                   verts[numOutputVerticesLimit])
{
    const float3 patchCenter = inputRecord.Get().position[gid];

    const int seed = CombineSeed(asuint(patchCenter.x), asuint(patchCenter.z));
    
    const int shroomType = numShroomTypes * Random(seed, 11002);
    
    const int vertsPerStem = 2 * shroomTypes[shroomType].stemPoints;
    const int vertsPerHat = 2 * shroomTypes[shroomType].hatPoints + 1;
    const int vertsPerShroom = vertsPerStem + vertsPerHat;
    
    const int trisPerStem = 2 * shroomTypes[shroomType].stemPoints;
    const int trisPerHat = 3 * shroomTypes[shroomType].hatPoints;
    const int trisPerShroom = trisPerStem + trisPerHat;    
   
    const int maxNumShrooms = min(numOutputVerticesLimit / vertsPerShroom, numOutputTrianglesLimit / trisPerShroom);

    const float radiusLookup[5] = {
        shroomTypes[shroomType].stemRingRadius,
        shroomTypes[shroomType].stemRingRadius,
        0.,
        shroomTypes[shroomType].hatRingInnerRadius,
        shroomTypes[shroomType].hatRingOuterRadius,
    };
    const float heightLookup[5] = {
        0.,
        0.1,
        .2,
        .2 - shroomTypes[shroomType].hatRingInnerDepth,
        .2 - shroomTypes[shroomType].hatRingOuterDepth,
    };
    
    
    const int numShrooms =
        min(maxNumShrooms, 1 + maxNumShrooms * pow(Random(seed, 99990001), shroomTypes[shroomType].shroomCountBiasPow));
        
    const int vertexCount   = numShrooms * vertsPerShroom;
    const int triangleCount = numShrooms * trisPerShroom;

    SetMeshOutputCounts(vertexCount, triangleCount);

    [[unroll]]
    for (int i = 0; i < numOutputTriangleIterations; ++i)
    {
        const int triId = gtid + mushroomGroupSize * i;

        if (triId < triangleCount) {
            const int shroomIdx = triId / trisPerShroom;
            int ti              = triId % trisPerShroom;

            const bool isHat = ti < trisPerHat;

            if (!isHat) {
                ti -= trisPerHat;
            }

            const int points = isHat ? shroomTypes[shroomType].hatPoints : shroomTypes[shroomType].stemPoints;
            const int ring   = ti / points;

            const int baseVertex = isHat ? (1 + (ring == 2) * points) : (vertsPerHat + ring * points);

            const int vi = ti - ring * points;

            const int a = baseVertex + vi;
            const int b = baseVertex + ((vi + 1) % points);
            int       c = (ring == 1) ? b : a;
            c += ((ring == 1) ^ !isHat) ? points : -points;
            c = max(c, 0);

            tris[triId] = shroomIdx * vertsPerShroom + uint3(a, b, c);
        }
    }

    [[unroll]]
    for (int i = 0; i < numOutputVertexIterations; ++i)
    {
        const int vertId = gtid + mushroomGroupSize * i;

        if (vertId < vertexCount) {
            const int shroomIdx = vertId / vertsPerShroom;
            int vi              = vertId % vertsPerShroom;
            float3    pos       = float3(0, 0, 0);
            bool      isHat     = vi < vertsPerHat;

            vi -= (!isHat) * vertsPerHat;

            int points = isHat ? shroomTypes[shroomType].hatPoints : shroomTypes[shroomType].stemPoints;

            int ring = (vi + (shroomTypes[shroomType].hatPoints - 1) * isHat) / points;

            float angle = frac((vi - isHat) / float(points));

            angle += (isHat && ring == 2) * -1. / (2 * points);

            angle *= 2 * PI;

            float radius = radiusLookup[2 * isHat + ring];

            pos.x += radius * cos(angle);
            pos.y += heightLookup[2 * isHat + ring];
            pos.z += radius * sin(angle);

            float theta = 2 * PI * shroomIdx / numShrooms + .1 * Random(seed, shroomIdx) * PI * 2;
            float rad   = sqrt(Random(seed, 19, shroomIdx)) * shroomTypes[shroomType].hatTilt;

            float3 offset = float3(sin(theta), 0, cos(theta));
            float3 dir    = rad * offset;

            dir.y = sqrt(1 - dir.x * dir.x - dir.z * dir.z);

            float3x3 rotation;
            rotation[0] = normalize(cross(dir, float3(0, 0, 1)));
            rotation[1] = dir;
            rotation[2] = normalize(cross(rotation[0], dir));
            rotation[0] = normalize(cross(dir, rotation[2]));

            if (isHat) {
                // add a little bit of noise
                pos.x += shroomTypes[shroomType].positionNoise * (2. * Random(vertId, 0xFEFA, seed) - 1.);
                pos.y += shroomTypes[shroomType].positionNoise * (2. * Random(vertId, 0xFEFB, seed) - 1.);
                pos.z += shroomTypes[shroomType].positionNoise * (2. * Random(vertId, 0xFEFC, seed) - 1.);

                pos = mul(transpose(rotation), pos);
            }

            float r = Random(seed, 877, shroomIdx);

            float distance = radiusMin + radiusV * r;

            static const float heightMin = .5;
            static const float heightV   = 1.;
            if (isHat || ring == 1) {
                pos.y += heightMin + heightV * (1 - r);
            }

            InsectVertex vertex;
            vertex.color.rgb = isHat ? shroomTypes[shroomType].hatColor : shroomTypes[shroomType].stemColor;
            if (!isHat && ring == 0) {
                vertex.color.xyz *= .1;
            }
            vertex.color.rgb *= 3.5;

            vertex.objectSpacePosition = scale * pos + distance * offset;

            ComputeClipSpacePositionAndMotion(vertex, patchCenter + vertex.objectSpacePosition);

            verts[vertId] = vertex;
        }
    }
}