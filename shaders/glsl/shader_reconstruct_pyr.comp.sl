#version 310 es

layout (local_size_x = 8, local_size_y = 8) in;

layout (binding = 0) readonly buffer Lap0BufY {
    uvec2 data[];
} lap0_buf_y;

layout (binding = 1) readonly buffer Lap0BufUV {
    uvec2 data[];
} lap0_buf_uv;

layout (binding = 2) readonly buffer Lap1BufY {
    uvec2 data[];
} lap1_buf_y;

layout (binding = 3) readonly buffer Lap1BufUV {
    uvec2 data[];
} lap1_buf_uv;

layout (binding = 4) writeonly buffer OutBufY {
    uvec2 data[];
} out_buf_y;

layout (binding = 5) writeonly buffer OutBufUV {
    uvec2 data[];
} out_buf_uv;

layout (binding = 6) readonly buffer PrevBlendBufY {
    uint data[];
} prev_blend_y;

layout (binding = 7) readonly buffer PrevBlendBufUV {
    uint data[];
} prev_blend_uv;

layout (binding = 8) readonly buffer MaskBuf {
    uvec2 data[];
} mask_buf;

uniform uint lap_img_width;
uniform uint lap_img_height;

uniform uint out_img_width;
uniform uint out_offset_x;

uniform uint prev_blend_img_width;
uniform uint prev_blend_img_height;

// normalization of gray level
const float norm_gl = 256.0f / 255.0f;

void reconstruct_y (uvec2 y_id, uvec2 blend_id);
void reconstruct_uv (uvec2 uv_id, uvec2 blend_id);

void main ()
{
    uvec2 g_id = gl_GlobalInvocationID.xy;

    uvec2 y_id = uvec2 (g_id.x, g_id.y * 4u);
    y_id.x = clamp (y_id.x, 0u, lap_img_width - 1u);

    uvec2 blend_id = uvec2 (g_id.x, g_id.y * 2u);
    blend_id.x = clamp (blend_id.x, 0u, prev_blend_img_width - 1u);
    reconstruct_y (y_id, blend_id);

    y_id.y += 2u;
    blend_id.y += 1u;
    reconstruct_y (y_id, blend_id);

    uvec2 uv_id = uvec2 (g_id.x, g_id.y * 2u);
    uv_id.x = clamp (uv_id.x, 0u, lap_img_width - 1u);
    blend_id = g_id;
    blend_id.x = clamp (blend_id.x, 0u, prev_blend_img_width - 1u);
    reconstruct_uv (uv_id, blend_id);
}

void reconstruct_y (uvec2 y_id, uvec2 blend_id)
{
    y_id.y = clamp (y_id.y, 0u, lap_img_height - 1u);
    blend_id.y = clamp (blend_id.y, 0u, prev_blend_img_height - 1u);

    uvec2 mask = mask_buf.data[y_id.x];
    vec4 mask0 = unpackUnorm4x8 (mask.x);
    vec4 mask1 = unpackUnorm4x8 (mask.y);

    uint idx = y_id.y * lap_img_width + y_id.x;
    uvec2 lap = lap0_buf_y.data[idx];
    vec4 lap00 = unpackUnorm4x8 (lap.x);
    vec4 lap01 = unpackUnorm4x8 (lap.y);

    lap = lap1_buf_y.data[idx];
    vec4 lap10 = unpackUnorm4x8 (lap.x);
    vec4 lap11 = unpackUnorm4x8 (lap.y);

    vec4 lap_blend0 = (lap00 - lap10) * mask0 + lap10;
    vec4 lap_blend1 = (lap01 - lap11) * mask1 + lap11;

    uint prev_blend_idx = blend_id.y * prev_blend_img_width + blend_id.x;
    vec4 prev_blend0 = unpackUnorm4x8 (prev_blend_y.data[prev_blend_idx]);
    vec4 prev_blend1 = unpackUnorm4x8 (prev_blend_y.data[prev_blend_idx + 1u]);
    prev_blend1 = (blend_id.x == prev_blend_img_width - 1u) ? prev_blend0.wwww : prev_blend1;

    vec4 inter = (prev_blend0 + vec4 (prev_blend0.yzw, prev_blend1.x)) * 0.5f;
    vec4 prev_blend_inter00 = vec4 (prev_blend0.x, inter.x, prev_blend0.y, inter.y);
    vec4 prev_blend_inter01 = vec4 (prev_blend0.z, inter.z, prev_blend0.w, inter.w);

    vec4 out0 = prev_blend_inter00 + lap_blend0 * 2.0f - norm_gl;
    vec4 out1 = prev_blend_inter01 + lap_blend1 * 2.0f - norm_gl;
    out0 = clamp (out0, 0.0f, 1.0f);
    out1 = clamp (out1, 0.0f, 1.0f);

    uint out_idx = y_id.y * out_img_width + out_offset_x + y_id.x;
    out_buf_y.data[out_idx] = uvec2 (packUnorm4x8 (out0), packUnorm4x8 (out1));

    idx = (y_id.y >= lap_img_height - 1u) ? idx : idx + lap_img_width;
    lap = lap0_buf_y.data[idx];
    lap00 = unpackUnorm4x8 (lap.x);
    lap01 = unpackUnorm4x8 (lap.y);

    lap = lap1_buf_y.data[idx];
    lap10 = unpackUnorm4x8 (lap.x);
    lap11 = unpackUnorm4x8 (lap.y);

    lap_blend0 = (lap00 - lap10) * mask0 + lap10;
    lap_blend1 = (lap01 - lap11) * mask1 + lap11;

    prev_blend_idx = (blend_id.y >= prev_blend_img_height - 1u) ? prev_blend_idx : prev_blend_idx + prev_blend_img_width;
    prev_blend0 = unpackUnorm4x8 (prev_blend_y.data[prev_blend_idx]);
    prev_blend1 = unpackUnorm4x8 (prev_blend_y.data[prev_blend_idx + 1u]);
    prev_blend1 = (blend_id.x == prev_blend_img_width - 1u) ? prev_blend0.wwww : prev_blend1;

    inter = (prev_blend0 + vec4 (prev_blend0.yzw, prev_blend1.x)) * 0.5f;
    vec4 prev_blend_inter10 = vec4 (prev_blend0.x, inter.x, prev_blend0.y, inter.y);
    vec4 prev_blend_inter11 = vec4 (prev_blend0.z, inter.z, prev_blend0.w, inter.w);
    prev_blend_inter10 = (prev_blend_inter00 + prev_blend_inter10) * 0.5f;
    prev_blend_inter11 = (prev_blend_inter01 + prev_blend_inter11) * 0.5f;

    out0 = prev_blend_inter10 + lap_blend0 * 2.0f - norm_gl;
    out1 = prev_blend_inter11 + lap_blend1 * 2.0f - norm_gl;
    out0 = clamp (out0, 0.0f, 1.0f);
    out1 = clamp (out1, 0.0f, 1.0f);

    out_idx += out_img_width;
    out_buf_y.data[out_idx] = uvec2 (packUnorm4x8 (out0), packUnorm4x8 (out1));
}

void reconstruct_uv (uvec2 uv_id, uvec2 blend_id)
{
    uv_id.y = clamp (uv_id.y, 0u, lap_img_height / 2u - 1u);
    blend_id.y = clamp (blend_id.y, 0u, prev_blend_img_height / 2u - 1u);

    uvec2 mask = mask_buf.data[uv_id.x];
    vec4 mask0 = unpackUnorm4x8 (mask.x);
    vec4 mask1 = unpackUnorm4x8 (mask.y);

    uint idx = uv_id.y * lap_img_width + uv_id.x;
    uvec2 lap = lap0_buf_uv.data[idx];
    vec4 lap00 = unpackUnorm4x8 (lap.x);
    vec4 lap01 = unpackUnorm4x8 (lap.y);

    lap = lap1_buf_uv.data[idx];
    vec4 lap10 = unpackUnorm4x8 (lap.x);
    vec4 lap11 = unpackUnorm4x8 (lap.y);

    mask0.yw = mask0.xz;
    mask1.yw = mask1.xz;
    vec4 lap_blend0 = (lap00 - lap10) * mask0 + lap10;
    vec4 lap_blend1 = (lap01 - lap11) * mask1 + lap11;

    uint prev_blend_idx = blend_id.y * prev_blend_img_width + blend_id.x;
    vec4 prev_blend0 = unpackUnorm4x8 (prev_blend_uv.data[prev_blend_idx]);
    vec4 prev_blend1 = unpackUnorm4x8 (prev_blend_uv.data[prev_blend_idx + 1u]);
    prev_blend1 = (blend_id.x == prev_blend_img_width - 1u) ? prev_blend0.zwzw : prev_blend1;

    vec4 inter = (prev_blend0 + vec4 (prev_blend0.zw, prev_blend1.xy)) * 0.5f;
    vec4 prev_blend_inter00 = vec4 (prev_blend0.xy, inter.xy);
    vec4 prev_blend_inter01 = vec4 (prev_blend0.zw, inter.zw);

    vec4 out0 = prev_blend_inter00 + lap_blend0 * 2.0f - norm_gl;
    vec4 out1 = prev_blend_inter01 + lap_blend1 * 2.0f - norm_gl;
    out0 = clamp (out0, 0.0f, 1.0f);
    out1 = clamp (out1, 0.0f, 1.0f);

    uint out_idx = uv_id.y * out_img_width + out_offset_x + uv_id.x;
    out_buf_uv.data[out_idx] = uvec2 (packUnorm4x8 (out0), packUnorm4x8 (out1));

    idx = (uv_id.y >= (lap_img_height / 2u - 1u)) ? idx : idx + lap_img_width;
    lap = lap0_buf_uv.data[idx];
    lap00 = unpackUnorm4x8 (lap.x);
    lap01 = unpackUnorm4x8 (lap.y);

    lap = lap1_buf_uv.data[idx];
    lap10 = unpackUnorm4x8 (lap.x);
    lap11 = unpackUnorm4x8 (lap.y);

    lap_blend0 = (lap00 - lap10) * mask0 + lap10;
    lap_blend1 = (lap01 - lap11) * mask1 + lap11;

    prev_blend_idx = (blend_id.y >= (prev_blend_img_height / 2u - 1u)) ?
                     prev_blend_idx : prev_blend_idx + prev_blend_img_width;
    prev_blend0 = unpackUnorm4x8 (prev_blend_uv.data[prev_blend_idx]);
    prev_blend1 = unpackUnorm4x8 (prev_blend_uv.data[prev_blend_idx + 1u]);
    prev_blend1 = (blend_id.x == prev_blend_img_width - 1u) ? prev_blend0.zwzw : prev_blend1;

    inter = (prev_blend0 + vec4 (prev_blend0.zw, prev_blend1.xy)) * 0.5f;
    vec4 prev_blend_inter10 = vec4 (prev_blend0.xy, inter.xy);
    vec4 prev_blend_inter11 = vec4 (prev_blend0.zw, inter.zw);
    prev_blend_inter10 = (prev_blend_inter00 + prev_blend_inter10) * 0.5f;
    prev_blend_inter11 = (prev_blend_inter01 + prev_blend_inter11) * 0.5f;

    out0 = prev_blend_inter10 + lap_blend0 * 2.0f - norm_gl;
    out1 = prev_blend_inter11 + lap_blend1 * 2.0f - norm_gl;
    out0 = clamp (out0, 0.0f, 1.0f);
    out1 = clamp (out1, 0.0f, 1.0f);

    out_idx += out_img_width;
    out_buf_uv.data[out_idx] = uvec2 (packUnorm4x8 (out0), packUnorm4x8 (out1));
}
