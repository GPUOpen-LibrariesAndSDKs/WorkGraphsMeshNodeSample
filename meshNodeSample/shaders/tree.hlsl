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

// Oak tree generation is single-threaded, so we use a coalescing node to generate multiple trees at once.
// Each oka tree consists of three splines: the trunk, a branch and the leafes.
// Thus we can process maxSplinesPerRecord (=32) trees in parallel
[Shader("node")]
[NodeId("GenerateTree", 0)]
[NodeLaunch("coalescing")]
[NumThreads(maxSplinesPerRecord, 1, 1)]
void GenerateOakTree(
    [MaxRecords(maxSplinesPerRecord)]
    GroupNodeInputRecords<GenerateTreeRecord> inputRecord,

    uint threadId : SV_GroupThreadID,

    [MaxRecords(3)]
    [NodeId("DrawSpline")]
    NodeOutput<DrawSplineRecord> output)
{
    GroupNodeOutputRecords<DrawSplineRecord> outputRecord = output.GetGroupNodeOutputRecords(3);

    if (threadId < inputRecord.Count()) {
        const float2 basePositionXZ = inputRecord.Get(threadId).position;
        const float3 basePosition   = GetTerrainPosition(basePositionXZ);

        const uint seed = CombineSeed(asuint(basePositionXZ.x), asuint(basePositionXZ.y));

        const float  rotationAngle = Random(seed, 78923) * 2 * PI;
        const float3 forward       = float3(sin(rotationAngle), 0, cos(rotationAngle));
        const float3 up            = lerp(float3(0, 1, 0), GetTerrainNormal(basePositionXZ), 0.1);
        const float3 side          = normalize(cross(forward, up));

        const float upScale   = lerp(0.5, 1.2, Random(seed, 546));
        const float sideScale = lerp(0.6, 1.0, Random(seed, 9487));

        const int splineIndex = threadId;

        // Tree trunk
        {
            // Set dispatch grid to number of splines per record
            outputRecord.Get(0).dispatchGrid                   = uint3(inputRecord.Count(), 1, 1);
            outputRecord.Get(0).color[splineIndex]             = float3(0.18, 0.12, 0.10) * 6;
            outputRecord.Get(0).rotationOffset[splineIndex]    = 0;
            outputRecord.Get(0).windStrength[splineIndex]      = float2(0, 0);
            outputRecord.Get(0).controlPointCount[splineIndex] = 5;

            int controlPointIndex = splineIndex * splineMaxControlPointCount;

            outputRecord.Get(0).controlPointPositions[controlPointIndex]       = basePosition - up;
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 5;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.5 * sideScale;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(0).controlPointPositions[controlPointIndex]       = basePosition + 2 * upScale * up;
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 4;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.35 * sideScale;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.5;
            controlPointIndex++;

            outputRecord.Get(0).controlPointPositions[controlPointIndex] =
                basePosition + 4 * upScale * up + 1 * sideScale * forward;
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 3;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.25 * sideScale;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(0).controlPointPositions[controlPointIndex] =
                basePosition + 4.5 * upScale * up + 1.5 * sideScale * forward + 0.5 * sideScale * side;
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 2;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.3 * sideScale;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(0).controlPointPositions[controlPointIndex] =
                basePosition + 5.5 * upScale * up + 2 * sideScale * forward + 1 * sideScale * side;
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 1;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.0;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
        }

        // Tree branch
        {
            outputRecord.Get(1).dispatchGrid                   = uint3(inputRecord.Count(), 1, 1);
            outputRecord.Get(1).color[splineIndex]             = float3(0.18, 0.12, 0.10) * 6;
            outputRecord.Get(1).rotationOffset[splineIndex]    = 0;
            outputRecord.Get(1).windStrength[splineIndex]      = float2(0, 0);
            outputRecord.Get(1).controlPointCount[splineIndex] = 3;

            int controlPointIndex = splineIndex * splineMaxControlPointCount;

            outputRecord.Get(1).controlPointPositions[controlPointIndex] =
                basePosition + 3 * upScale * up + 0.5 * sideScale * forward;
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex]    = 4;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]           = 0.25 * sideScale;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(1).controlPointPositions[controlPointIndex] =
                basePosition + 4 * upScale * up - 0.5 * sideScale * forward;
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex]    = 3;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]           = 0.2 * sideScale;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.25;
            controlPointIndex++;

            outputRecord.Get(1).controlPointPositions[controlPointIndex] =
                basePosition + 5 * upScale * up - 1 * sideScale * forward;
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex]    = 1;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]           = 0.0;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
        }

        // Tree leaves
        {
            outputRecord.Get(2).dispatchGrid       = uint3(inputRecord.Count(), 1, 1);
            outputRecord.Get(2).color[splineIndex] = float3(0.3, 0.3, 0.0) * lerp(0.7, 1.3, Random(seed, 1456));
            outputRecord.Get(2).rotationOffset[splineIndex]    = rotationAngle;
            outputRecord.Get(2).windStrength[splineIndex]      = float2(0.125, 0.5);
            outputRecord.Get(2).controlPointCount[splineIndex] = 4;

            int controlPointIndex = splineIndex * splineMaxControlPointCount;

            outputRecord.Get(2).controlPointPositions[controlPointIndex] =
                basePosition + 4 * upScale * up + 0.5 * sideScale * forward;
            outputRecord.Get(2).controlPointVertexCounts[controlPointIndex]    = 1;
            outputRecord.Get(2).controlPointRadii[controlPointIndex]           = 0.0;
            outputRecord.Get(2).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(2).controlPointPositions[controlPointIndex] =
                basePosition + 5 * upScale * up + 0.5 * sideScale * forward;
            outputRecord.Get(2).controlPointVertexCounts[controlPointIndex]    = round(lerp(5, 7, Random(seed, 2156)));
            outputRecord.Get(2).controlPointRadii[controlPointIndex]           = float2(2.5, 4) * sideScale;
            outputRecord.Get(2).controlPointNoiseAmplitudes[controlPointIndex] = 0.7 * upScale;
            controlPointIndex++;

            outputRecord.Get(2).controlPointPositions[controlPointIndex] =
                basePosition + 6.5 * upScale * up + 0.5 * sideScale * forward;
            outputRecord.Get(2).controlPointVertexCounts[controlPointIndex]    = round(lerp(3, 5, Random(seed, 458)));
            outputRecord.Get(2).controlPointRadii[controlPointIndex]           = 3.5 * sideScale;
            outputRecord.Get(2).controlPointNoiseAmplitudes[controlPointIndex] = 0.7 * upScale;
            controlPointIndex++;

            outputRecord.Get(2).controlPointPositions[controlPointIndex] =
                basePosition + 8.5 * upScale * up + 0.5 * sideScale * forward + 0.5 * sideScale * side;
            outputRecord.Get(2).controlPointVertexCounts[controlPointIndex]    = 1;
            outputRecord.Get(2).controlPointRadii[controlPointIndex]           = 0.0;
            outputRecord.Get(2).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
        }
    }

    outputRecord.OutputComplete();
}

// Pine tree generation works the same way as the oak tree generation.
// Each pine tree consists of two splines: the tree trunk and the "leaves".
[Shader("node")]
[NodeId("GenerateTree", 1)]
[NodeLaunch("coalescing")]
[NumThreads(maxSplinesPerRecord, 1, 1)]
void GeneratePineTree(
    [MaxRecords(maxSplinesPerRecord)]
    GroupNodeInputRecords<GenerateTreeRecord> inputRecord,

    uint threadId : SV_GroupThreadID,

    [MaxRecords(2)]
    [NodeId("DrawSpline")]
    NodeOutput<DrawSplineRecord> output)
{
    GroupNodeOutputRecords<DrawSplineRecord> outputRecord = output.GetGroupNodeOutputRecords(2);

    if (threadId < inputRecord.Count()) {
        const float2 basePositionXZ = inputRecord.Get(threadId).position;
        const float3 basePosition   = GetTerrainPosition(basePositionXZ);
        const float3 terrainNormal  = GetTerrainNormal(basePositionXZ);
        const float3 basePositionUp = lerp(float3(0, 1, 0), terrainNormal, 0.1);

        const uint seed = CombineSeed(asuint(basePositionXZ.x), asuint(basePositionXZ.y));

        const float stemTerrainFactor = 1.f + (1.f - smoothstep(0.6, 1.0, terrainNormal.y)) * 0.5;

        const float rotationAngle    = Random(seed, 14658) * 2 * PI;
        const float stemHeight       = 1 + Random(seed, 2384) * 2 * stemTerrainFactor;
        const float leafRadiusScale  = 1.5 + Random(seed, 3827);
        const float leafSectionScale = 1.5 + Random(seed, 78934) * 2 * stemTerrainFactor;

        const int splineIndex = threadId;

        // Tree trunk
        {
            outputRecord.Get(0).dispatchGrid                    = uint3(inputRecord.Count(), 1, 1);
            outputRecord.Get(0).color[splineIndex]             = float3(1.08, 0.72, 0.6);
            outputRecord.Get(0).rotationOffset[splineIndex]    = rotationAngle;
            outputRecord.Get(0).windStrength[splineIndex]      = float2(0.125, 0);
            outputRecord.Get(0).controlPointCount[splineIndex] = 2;

            int controlPointIndex = splineIndex * splineMaxControlPointCount;

            outputRecord.Get(0).controlPointPositions[controlPointIndex]       = basePosition - basePositionUp * 4.f;
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 5;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.4;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(0).controlPointPositions[controlPointIndex] =
                basePosition + float3(0, stemHeight + 0.5, 0);
            outputRecord.Get(0).controlPointVertexCounts[controlPointIndex]    = 4;
            outputRecord.Get(0).controlPointRadii[controlPointIndex]           = 0.3;
            outputRecord.Get(0).controlPointNoiseAmplitudes[controlPointIndex] = 0;
        }

        // Tree leaves
        {
            const float  green      = saturate(PerlinNoise2D(0.05 * basePositionXZ));
            const float  brightness = PerlinNoise2D(0.4 * basePositionXZ + float2(498, 345));
            const float3 color      = float3(0.24, 0.25 + green * 0.15, 0.0) * (1.0 + brightness * 0.4);

            outputRecord.Get(1).dispatchGrid                   = uint3(inputRecord.Count(), 1, 1);
            outputRecord.Get(1).color[splineIndex]             = color;
            outputRecord.Get(1).rotationOffset[splineIndex]    = rotationAngle;
            outputRecord.Get(1).windStrength[splineIndex]      = float2(0.125, 0.5);
            outputRecord.Get(1).controlPointCount[splineIndex] = 7;

            int controlPointIndex = splineIndex * splineMaxControlPointCount;

            const float ringHeight0                                         = stemHeight;
            outputRecord.Get(1).controlPointPositions[controlPointIndex]    = basePosition + float3(0, ringHeight0, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex] = 1;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]        = 0.0;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;

            outputRecord.Get(1).controlPointPositions[controlPointIndex] =
                basePosition + float3(0, ringHeight0 + 0.5, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex]    = 7;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]           = leafRadiusScale;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.2;
            controlPointIndex++;

            const float ringHeight1                                         = stemHeight + 1 * leafSectionScale;
            outputRecord.Get(1).controlPointPositions[controlPointIndex]    = basePosition + float3(0, ringHeight1, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex] = 7;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]        = leafRadiusScale * 0.3;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.1;
            controlPointIndex++;

            outputRecord.Get(1).controlPointPositions[controlPointIndex] =
                basePosition + float3(0, ringHeight1 + 0.5, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex]    = 7;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]           = leafRadiusScale * 0.8;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.2;
            controlPointIndex++;

            const float ringHeight2                                         = stemHeight + 2 * leafSectionScale;
            outputRecord.Get(1).controlPointPositions[controlPointIndex]    = basePosition + float3(0, ringHeight2, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex] = 7;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]        = leafRadiusScale * 0.3;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.1;
            controlPointIndex++;

            outputRecord.Get(1).controlPointPositions[controlPointIndex] =
                basePosition + float3(0, ringHeight2 + 0.5, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex]    = 7;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]           = leafRadiusScale * 0.6;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.2;
            controlPointIndex++;

            const float ringHeight3                                         = stemHeight + 3 * leafSectionScale;
            outputRecord.Get(1).controlPointPositions[controlPointIndex]    = basePosition + float3(0, ringHeight3, 0);
            outputRecord.Get(1).controlPointVertexCounts[controlPointIndex] = 1;
            outputRecord.Get(1).controlPointRadii[controlPointIndex]        = 0.0;
            outputRecord.Get(1).controlPointNoiseAmplitudes[controlPointIndex] = 0.0;
            controlPointIndex++;
        }
    }

    outputRecord.OutputComplete();
}