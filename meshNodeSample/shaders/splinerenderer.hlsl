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

struct TransformedVertex {
    float4 clipSpacePosition : SV_POSITION;
    float3 objectSpacePosition : NORMAL0;
    float2 clipSpaceMotion : TEXCOORD0;
    float3 color : NORMAL1;
};

// Returns number of line sections in a vertex ring
int GetRingSectionCount(in int ringVertexCount) {
    return ringVertexCount == 1 ? 0 : ringVertexCount;
}

static const int splineGroupSize         = 128;
static const int numOutputVerticesLimit  = 64;
static const int numOutputTrianglesLimit = 128;

[Shader("node")]
[NodeLaunch("mesh")]
[NodeId("DrawSpline", 0)]
[NodeMaxDispatchGrid(maxSplinesPerRecord, 1, 1)]
// This limit was set through instrumentation and is not required on AMD GPUs.
// If you wish to change any of the procedural generation parameters,
// and you are running on a non-AMD GPU, you may need to adjust this limit.
// You can learn more at: 
// https://gpuopen.com/learn/work_graphs_mesh_nodes/work_graphs_mesh_nodes-tips_tricks_best_practices
[NodeMaxInputRecordsPerGraphEntryRecord(10000, true)]
[NumThreads(splineGroupSize, 1, 1)]
[OutputTopology("triangle")]
void SplineMeshShader(
    uint                                      threadId : SV_GroupThreadID,
    uint                                      gid : SV_GroupID,
    DispatchNodeInputRecord<DrawSplineRecord> inputRecord,
    out indices uint3                         tris[numOutputTrianglesLimit],
    out vertices TransformedVertex            verts[numOutputVerticesLimit])
{
    const uint splineControlPointCount = clamp(inputRecord.Get().controlPointCount[gid], 0, splineMaxControlPointCount);
    const uint splineSectionCount      = clamp(int(splineControlPointCount) - 1, 0, splineMaxControlPointCount - 1);

    const uint controlPointOffset = gid * splineMaxControlPointCount;

    uint vertexOutputCount    = 0;
    uint primitiveOutputCount = 0;

    // control point for which the current thread will create a vertex
    int threadVertexControlPoint       = 0;
    // index on control point ring which the current thread will generate
    int threadVertexControlPointVertex = 0;

    // control point section for which the current thread will create a triangle
    int threadPrimitiveSection                     = 0;
    // index on control point ring which the current thread will generate
    int threadPrimitiveSectionTriangle             = 0;
    int threadPrimitiveSectionVertexOffset = 0;

    {
        // Number of vertices in last vertex ring
        int lastRingVertexCount = 0;

        // count vertices in first ring
        {
            const int controlPointVertexCount = inputRecord.Get().controlPointVertexCounts[controlPointOffset];

            // check if current thread will generate a vertex on this ring
            if (threadId < controlPointVertexCount)
            {
                threadVertexControlPoint       = 0;
                threadVertexControlPointVertex = threadId;
            }

            // Count total number of vertices
            vertexOutputCount += controlPointVertexCount;

            // Update last ring size
            lastRingVertexCount = controlPointVertexCount;
        }

        // count vertex & triangles count for every ring
        for (int ring = 1; ring < splineControlPointCount; ++ring)
        {
            const int controlPointVertexCount = inputRecord.Get().controlPointVertexCounts[controlPointOffset + ring];

            if ((vertexOutputCount <= threadId) && ((vertexOutputCount + controlPointVertexCount) > threadId))
            {
                threadVertexControlPoint       = ring;
                threadVertexControlPointVertex = threadId - int(vertexOutputCount);
            }

            // lower sections are on last ring
            const int lowerSectionCount = GetRingSectionCount(lastRingVertexCount);
            // upper sections are on current ring
            const int upperSectionCount = GetRingSectionCount(controlPointVertexCount);

            // Count number of regular sections (i.e. one edge of the lower ring maps to one section on the upper ring)
            const int sectionCount         = min(lowerSectionCount, upperSectionCount);
            const int regularTriangleCount = sectionCount * 2;
            // Count number of irregular trianlges (i.e. a edge connects with a single vertex on the other ring)
            const int irregularTriangleCount = max(lowerSectionCount, upperSectionCount) - sectionCount;

            // Total number of triangles on this ring
            const int triangleCount = regularTriangleCount + irregularTriangleCount;

            if ((primitiveOutputCount <= threadId) && ((primitiveOutputCount + triangleCount) > threadId))
            {
                // Primitives are generated from lower to upper ring, i.e. we need the index of the last ring
                threadPrimitiveSection         = ring - 1;
                threadPrimitiveSectionTriangle = threadId - primitiveOutputCount;
                // Get index of first vertex in last ring
                threadPrimitiveSectionVertexOffset = vertexOutputCount - lastRingVertexCount;
            }

            // Count total number of vertices & triangles
            vertexOutputCount += controlPointVertexCount;
            primitiveOutputCount += triangleCount;

            // Update last ring size
            lastRingVertexCount = controlPointVertexCount;
        }
    }

    vertexOutputCount = min(vertexOutputCount, numOutputVerticesLimit);
    primitiveOutputCount = min(primitiveOutputCount, numOutputTrianglesLimit);
    
    SetMeshOutputCounts(vertexOutputCount, primitiveOutputCount);

    if (threadId < vertexOutputCount) {
        TransformedVertex vertex;

        // Base position to compute object-local positions
        const float3 splineBasePosition = inputRecord.Get().controlPointPositions[controlPointOffset];

        const float3 controlPointPosition    = inputRecord.Get().controlPointPositions[controlPointOffset + threadVertexControlPoint];
        const uint   controlPointVertexCount = inputRecord.Get().controlPointVertexCounts[controlPointOffset + threadVertexControlPoint];

        // Compute forward vector based on previous and next control point positions
        float3 forward = float3(0, 0, 0);
        // Add direction from previous control point
        if (threadVertexControlPoint > 0)
        {
            const float3 previousControlPointPosition = inputRecord.Get().controlPointPositions[controlPointOffset + threadVertexControlPoint - 1];
            forward += controlPointPosition - previousControlPointPosition;
        }
        // Add direction to next control point
        if (threadVertexControlPoint < (splineControlPointCount - 1))
        {
            const float3 nextControlPointPosition = inputRecord.Get().controlPointPositions[controlPointOffset + threadVertexControlPoint + 1];
            forward += nextControlPointPosition - controlPointPosition;
        }

        forward = normalize(forward);

        // get perpendicular vector to forward
        float3 right = normalize(cross(forward, float3(1, 0, 0)));
        float3 up    = normalize(cross(forward, right));

        const float rotationOffset = inputRecord.Get().rotationOffset[gid];
        const float vertexAlpha    = rotationOffset + (threadVertexControlPointVertex / float(controlPointVertexCount)) * 2.f * PI;

        const float2 radius         = inputRecord.Get().controlPointRadii[controlPointOffset + threadVertexControlPoint];
        const float  noiseAmplitude = inputRecord.Get().controlPointNoiseAmplitudes[controlPointOffset + threadVertexControlPoint];

        // random noise value in [-noiseAmplitude; noiseAmplitude]
        const float noise = (Random(Hash(controlPointPosition), Hash(vertexAlpha)) * 2.0 - 1.0) * noiseAmplitude;

        const float3 worldSpaceBasePosition =
            controlPointPosition +                 // base position
            cos(vertexAlpha) * right * radius.y +  // position on vertex ring in right direction
            sin(vertexAlpha) * up * radius.x +     // position on vertex ring in up direction
            forward * noise;                       // random noise offset in spline direction

        // x = wind strength for current spline
        // y = factor for how much the actual vertex position in influencing the wind offset
        //     0 = wind offset is only determined by control point position
        //     1 = wind offset is only determined by vertex position
        const float2 windStrength          = inputRecord.Get().windStrength[gid];
        const float3 windReferencePosition = lerp(controlPointPosition, worldSpaceBasePosition, windStrength.y);
        // Get Height above terrain scaled by wind strength
        const float vertexHeight = max(windReferencePosition.y - GetTerrainHeight(windReferencePosition.xz), 0) * windStrength.x;

        // Compute wind offset for current and last frame
        const float3 windOffset =
            vertexHeight * GetWindStrength() * GetWindOffset(windReferencePosition.xz, GetTime());
        const float3 previousWindOffset =
            vertexHeight * GetWindStrength() * GetWindOffset(windReferencePosition.xz, GetPreviousTime());

        // compute position relative to first control point
        // this improve floating-point precision of ddx & ddy derivatives in pixel shader
        vertex.objectSpacePosition = worldSpaceBasePosition - splineBasePosition + windOffset;
        vertex.color               = inputRecord.Get().color[gid];

        ComputeClipSpacePositionAndMotion(
            vertex, worldSpaceBasePosition + windOffset, worldSpaceBasePosition + previousWindOffset);


        verts[threadId] = vertex;
    }

    if (threadId < primitiveOutputCount) {
        // Get number of vertices in current (lower) and next (upper) ring
        const int lowerVertexCount = inputRecord.Get().controlPointVertexCounts[controlPointOffset + threadPrimitiveSection];
        const int upperVertexCount = inputRecord.Get().controlPointVertexCounts[controlPointOffset + threadPrimitiveSection + 1];

        // Get number of sections in current and next ring
        const int lowerSectionCount = GetRingSectionCount(lowerVertexCount);
        const int upperSectionCount = GetRingSectionCount(upperVertexCount);

        // Get index of first vertex in current and next ring
        const int lowerVertexOffset = threadPrimitiveSectionVertexOffset;
        const int upperVertexOffset = lowerVertexOffset + lowerVertexCount;

        // The number of full sections (i.e. one edge in the lower ring corresponds to one edge in the upper ring)
        // is determined by the smaller vertex ring.
        // Irregular triangles will be generated from the larger ring towards the smaller ring
        const bool isLower = lowerSectionCount <= upperSectionCount;

        // Total number of regular sections
        const int sectionCount = isLower ? lowerSectionCount : upperSectionCount;
        // Ratio between sections in the smaller and larger ring
        const float sectionFactor = isLower ? upperSectionCount / float(lowerSectionCount) : lowerSectionCount / float(upperSectionCount);

        const int regularTriangleCount = sectionCount * 2;
        // check if current triangle is irregular (i.e. connects an edge to a single vertex)
        const bool isIrregularTriangle = threadPrimitiveSectionTriangle >= regularTriangleCount;
        // index of irregular triangle
        const int irregularTriangleIndex = threadPrimitiveSectionTriangle - regularTriangleCount;

        // running counters
        int lowerSection     = 0;
        int upperSection     = 0;
        int sectionJumpCount = 0;

        // indices for smaller and larger (=other) section
        int section      = 0;
        int otherSection = 0;
        for (; section < sectionCount; ++section)
        {
            // compute which section on the larger ring should match up with the current section
            int otherSectionTarget = section * sectionFactor;

            // Generate irregular triangles for skipped sections
            for (; otherSection < otherSectionTarget; ++otherSection)
            {
                if (isIrregularTriangle && (sectionJumpCount == irregularTriangleIndex))
                {
                    lowerSection = isLower ? section : otherSection;
                    upperSection = isLower ? otherSection : section;
                }
                sectionJumpCount++;
            }

            // Generate a regular triangles for both sections
            if (!isIrregularTriangle && (section == (threadPrimitiveSectionTriangle / 2)))
            {
                lowerSection = isLower ? section : otherSection;
                upperSection = isLower ? otherSection : section;
            }

            otherSection++;
        }
        // Generate remaining irregular triangles to close the ring
        for (; otherSection < max(lowerSectionCount, upperSectionCount); ++otherSection)
        {
            if (isIrregularTriangle && (sectionJumpCount == irregularTriangleIndex))
            {
                lowerSection = isLower ? section : otherSection;
                upperSection = isLower ? otherSection : section;
            }
            sectionJumpCount++;
        }

        uint3 tri = 0;

        if (isIrregularTriangle) {
            if (isLower) {
                tri = uint3(lowerVertexOffset + ((lowerSection + 1) % lowerVertexCount),
                            upperVertexOffset + ((upperSection + 1) % upperVertexCount),        
                            upperVertexOffset + ((upperSection + 0) % upperVertexCount));
            } else {
                tri = uint3(lowerVertexOffset + ((lowerSection + 0) % lowerVertexCount),
                            lowerVertexOffset + ((lowerSection + 1) % lowerVertexCount),
                            upperVertexOffset + ((upperSection + 0) % upperVertexCount));
            }
        } else {
            if (threadPrimitiveSectionTriangle & 0x1) {
                tri = uint3(upperVertexOffset + ((upperSection + 0) % upperVertexCount),
                            lowerVertexOffset + ((lowerSection + 1) % lowerVertexCount),
                            upperVertexOffset + ((upperSection + 1) % upperVertexCount));
            } else {
                tri = uint3(lowerVertexOffset + ((lowerSection + 0) % lowerVertexCount),
                            lowerVertexOffset + ((lowerSection + 1) % lowerVertexCount),
                            upperVertexOffset + ((upperSection + 0) % upperVertexCount));
            }
        }

        tris[threadId] = tri;
    }
}

DeferredPixelShaderOutput SplinePixelShader(TransformedVertex input)
{
    DeferredPixelShaderOutput output;

    output.baseColor = float4(input.color, 1);
    output.motion    = input.clipSpaceMotion;

    // compute normal from object space position derivatives
    output.normal.xyz = normalize(cross(ddy(input.objectSpacePosition.xyz), ddx(input.objectSpacePosition.xyz)));
    output.normal.w   = 1.0;
    
    return output;
}