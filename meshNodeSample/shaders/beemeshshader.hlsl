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

// Static "vertex buffer" for bees
static const int    numBeeVertices               = 11;
static const float3 beePositions[numBeeVertices] = {
    float3(0.84, 0.0, -0.0),
    float3(-1.0, 0.0, -0.0),
    float3(-0.083, 0.722, -0.682),
    float3(-0.083, 0.722, 0.682),
    float3(1.063, 0.361, -0.275),
    float3(1.063, 0.361, 0.275),
    float3(0.353, 0.6, 0.0),
    float3(-0.283, 1.283, 1.415),
    float3(0.753, 1.228, 1.865),
    float3(-0.283, 1.283, -1.415),
    float3(0.753, 1.228, -1.865),
};
// Static vertex color attributes
static const float3 beeColors[numBeeVertices] = {
    float3(0.72, 0.56, 0.032),
    float3(0, 0, 0),
    float3(0.72, 0.56, 0.032),
    float3(0.72, 0.56, 0.032),
    float3(0, 0, 0),
    float3(0, 0, 0),

    float3(0.85, 0.85, 0.85),
    float3(0.85, 0.85, 0.85),
    float3(0.85, 0.85, 0.85),
    float3(0.85, 0.85, 0.85),
    float3(0.85, 0.85, 0.85),
};

// Static "index buffer" for bees
static const int   numBeeTriangles               = 10;
static const uint3 beeTriangles[numBeeTriangles] = {
    uint3(1, 3, 2),
    uint3(4, 5, 0),
    uint3(9, 6, 10),
    uint3(2, 5, 4),
    uint3(7, 6, 8),
    uint3(5, 3, 0),
    uint3(3, 1, 0),
    uint3(4, 0, 2),
    uint3(2, 0, 1),
    uint3(3, 5, 2),
};

float3 GetInsectPosition(float time)
{
    return 1.2 * float3(PerlinNoise2D(float2(time * 0.001, 0)),
                        PerlinNoise2D(float2(time * 0.001, 5)),
                        PerlinNoise2D(float2(time * 0.001, 9)));
}

static const int beeGroupSize = 128;

// customizable bee limit
static const int maxNumBees         = min(32, min(256 / numBeeVertices, 192 / numBeeTriangles));
static const int numOutputVertices  = maxNumBees * numBeeVertices;
static const int numOutputTriangles = maxNumBees * numBeeTriangles;

static const int numOutputVertexIterations = (numOutputVertices + (beeGroupSize - 1)) / beeGroupSize;
static const int numOutputTriangleIterations = (numOutputTriangles + (beeGroupSize - 1)) / beeGroupSize;

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawBees", 0)]
[NodeMaxDispatchGrid(maxInsectsPerRecord, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(20, true)]
[NumThreads(beeGroupSize, 1, 1)]
[OutputTopology("triangle")]
void BeeMeshShader(
    uint                                      gtid : SV_GroupThreadID,
    uint                                      gid : SV_GroupID,
    DispatchNodeInputRecord<DrawInsectRecord> inputRecord,
    out indices uint3                         tris[numOutputTriangles],
    out vertices InsectVertex                 verts[numOutputVertices])
{
    const int numBees       = maxNumBees;
    const int vertexCount   = numBees * numBeeVertices;
    const int triangleCount = numBees * numBeeTriangles;

    SetMeshOutputCounts(vertexCount, triangleCount);

    const float3 patchCenter = inputRecord.Get().position[gid];
    const int    seed        = CombineSeed(asuint(patchCenter.x), asuint(patchCenter.z));

    [[unroll]]
    for (int i = 0; i < numOutputTriangleIterations; ++i)
    {
        const int triId = gtid + beeGroupSize * i;

        if (triId < triangleCount) {
            const int insectId         = triId / numBeeTriangles;
            const int insectTriangleId = triId % numBeeTriangles;

            tris[triId] = beeTriangles[insectTriangleId] + insectId * numBeeVertices;
        }
    }

    [[unroll]]
    for (int i = 0; i < numOutputVertexIterations; ++i)
    {
        const int vertId = gtid + beeGroupSize * i;

        if (vertId < vertexCount) {
            const int insectId       = vertId / numBeeVertices;
            const int insectVertexId = vertId % numBeeVertices;

            // start time before night start
            const float nightStart = nightStartTime - Random(seed, 7843);
            // end time after night end
            const float nightEnd   = nightEndTime + Random(seed, 732);

            // scale insects to 0 at night
            const float nightScale    = max(smoothstep(nightStart - 1, nightStart, GetTimeOfDay()),
                                         1 - smoothstep(nightEnd, nightEnd + 1, GetTimeOfDay()));
            // slowly scale insects to 0 in the distance
            // for simplicity, we omit this scaling from the motion vector, as it only affects very distant insects
            const float distanceScale =
                smoothstep(beeFadeStartDistance, beeMaxDistance, distance(patchCenter, GetCameraPosition()));

            const float scale = (.01 + 0.03 * Random(seed, insectId, 8)) * (1 - nightScale) * (1 - distanceScale);

            // radius scale for positioning insects
            static const float R      = 0.2;
            const float        angle  = 2 * PI * Random(seed, insectId, 8);
            const float        radius = sqrt(R * Random(seed, insectId, 98));

            // compute random position offset for insect
            // insects will rotate around this position
            const float3 insectBasePosition =
                float3(radius * cos(angle), 0.75 + 0.5 * Random(seed, insectId, 988), radius * sin(angle));

            const float timeOffset = 1e6 * Random(seed, insectId, 55);
            const float time       = GetTime() + timeOffset;
            const float timePrev   = GetPreviousTime() + timeOffset;

            // compute local insect position offsets
            const float3 insectPositionOffset          = GetInsectPosition(time);
            const float3 insectPositionOffsetDelta     = GetInsectPosition(time - 10);
            const float3 prevInsectPositionOffset      = GetInsectPosition(timePrev);
            const float3 prevInsectPositionOffsetDelta = GetInsectPosition(timePrev - 10);

            const float3 insectPosition     = insectBasePosition + insectPositionOffset;
            const float3 prevInsectPosition = insectBasePosition + prevInsectPositionOffset;

            // compute forward vectors for rotating insects to face movement direction
            const float2 forward     = normalize(insectPositionOffset.xz - insectPositionOffsetDelta.xz);
            const float2 prevForward = normalize(prevInsectPositionOffset.xz - prevInsectPositionOffsetDelta.xz);

            float3 vertexPosition     = beePositions[insectVertexId] * scale;
            float3 prevVertexPosition = vertexPosition;
            
            // rotate wing vertices around insect center
            if (insectVertexId > 6) {
                // compute wing animation angle
                static const float wingDownAngle = -0.15;
                static const float wingAmplitude = 0.4;
                const float        phase         = wingDownAngle + wingAmplitude * cos(2 * PI * frac(time * 0.005));
                const float        phasePrev     = wingDownAngle + wingAmplitude * cos(2 * PI * frac(timePrev * 0.005));
            
                // insect center for rotating wings
                static const float3 rotatePoint = beePositions[6] * scale;

                float wingAngle       = sign(vertexPosition.z) * phase;
                float prevWingAngle   = sign(vertexPosition.z) * phasePrev;
                vertexPosition.yz     = RotateAroundPoint2d(vertexPosition.yz, wingAngle, rotatePoint.yz);
                prevVertexPosition.yz = RotateAroundPoint2d(prevVertexPosition.yz, prevWingAngle, rotatePoint.yz);
            }
            // rotate insect towards movement direction
            vertexPosition.xz     = float2(vertexPosition.x * forward.x - vertexPosition.z * forward.y,
                                       vertexPosition.x * forward.y + vertexPosition.z * forward.x);
            prevVertexPosition.xz = float2(prevVertexPosition.x * prevForward.x - prevVertexPosition.z * prevForward.y,
                                           prevVertexPosition.x * prevForward.y + prevVertexPosition.z * prevForward.x);

            InsectVertex vertex;
            vertex.objectSpacePosition = insectPosition + vertexPosition;
            vertex.color               = beeColors[insectVertexId];

            ComputeClipSpacePositionAndMotion(vertex,
                                              patchCenter + vertex.objectSpacePosition,
                                              patchCenter + prevInsectPosition + prevVertexPosition);

            verts[vertId] = vertex;
        }
    }
}