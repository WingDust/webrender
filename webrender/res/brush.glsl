/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifdef WR_VERTEX_SHADER

void brush_vs(
    int prim_address,
    vec2 local_pos,
    RectWithSize local_rect,
    ivec2 user_data
);

// Whether this brush is being drawn on a Picture
// task (new) or an alpha batch task (legacy).
// Can be removed once everything uses pictures.
#define BRUSH_FLAG_USES_PICTURE     (1 << 0)

struct BrushInstance {
    int picture_address;
    int prim_address;
    int layer_address;
    int clip_address;
    int z;
    int flags;
    ivec2 user_data;
};

BrushInstance load_brush() {
	BrushInstance bi;

    bi.picture_address = aData0.x;
    bi.prim_address = aData0.y;
    bi.layer_address = aData0.z;
    bi.clip_address = aData0.w;
    bi.z = aData1.x;
    bi.flags = aData1.y;
    bi.user_data = aData1.zw;

    return bi;
}

/*
 The dynamic picture that this brush exists on. Right now, it
 contains minimal information. In the future, it will describe
 the transform mode of primitives on this picture, among other things.
 */
struct PictureTask {
    RectWithSize target_rect;
};

PictureTask fetch_picture_task(int index) {
    ivec2 uv = get_fetch_uv(index, VECS_PER_RENDER_TASK);

    vec4 target_rect = TEXEL_FETCH(sRenderTasks, uv, 0, ivec2(0, 0));

    PictureTask task = PictureTask(RectWithSize(target_rect.xy, target_rect.zw));

    return task;
}

void main(void) {
    // Load the brush instance from vertex attributes.
    BrushInstance brush = load_brush();

    // Load the geometry for this brush. For now, this is simply the
    // local rect of the primitive. In the future, this will support
    // loading segment rects, and other rect formats (glyphs).
    PrimitiveGeometry geom = fetch_primitive_geometry(brush.prim_address);

    vec2 device_pos, local_pos;
    RectWithSize local_rect = geom.local_rect;

    if ((brush.flags & BRUSH_FLAG_USES_PICTURE) != 0) {
        // Fetch the dynamic picture that we are drawing on.
        PictureTask pic_task = fetch_picture_task(brush.picture_address);

        // Right now - pictures only support local positions. In the future, this
        // will be expanded to support transform picture types (the common kind).
        device_pos = pic_task.target_rect.p0 + aPosition.xy * pic_task.target_rect.size;
        local_pos = aPosition.xy * pic_task.target_rect.size / uDevicePixelRatio;

        // Write the final position transformed by the orthographic device-pixel projection.
        gl_Position = uTransform * vec4(device_pos, 0.0, 1.0);
    } else {
        AlphaBatchTask alpha_task = fetch_alpha_batch_task(brush.picture_address);
        Layer layer = fetch_layer(brush.layer_address);
        ClipArea clip_area = fetch_clip_area(brush.clip_address);

        // Write the normal vertex information out.
        // TODO(gw): Support transform types in brushes. For now,
        //           the old cache image shader didn't support
        //           them yet anyway, so we're not losing any
        //           existing functionality.
        VertexInfo vi = write_vertex(
            geom.local_rect,
            geom.local_clip_rect,
            float(brush.z),
            layer,
            alpha_task,
            geom.local_rect
        );

        local_pos = vi.local_pos;

        // For brush instances in the alpha pass, always write
        // out clip information.
        // TODO(gw): It's possible that we might want alpha
        //           shaders that don't clip in the future,
        //           but it's reasonable to assume that one
        //           implies the other, for now.
#ifdef WR_FEATURE_ALPHA_PASS
        write_clip(
            vi.screen_pos,
            clip_area
        );
#endif
    }

    // Run the specific brush VS code to write interpolators.
    brush_vs(
        brush.prim_address + VECS_PER_PRIM_HEADER,
        local_pos,
        local_rect,
        brush.user_data
    );
}
#endif

#ifdef WR_FRAGMENT_SHADER

vec4 brush_fs();

void main(void) {
    // Run the specific brush FS code to output the color.
    vec4 color = brush_fs();

#ifdef WR_FEATURE_ALPHA_PASS
    // Apply the clip mask
    color *= do_clip();
#endif

    // TODO(gw): Handle pre-multiply common code here as required.
    oFragColor = color;
}
#endif
