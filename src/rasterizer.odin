package idunn

import "base:runtime"
import "core:io"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"


ScreenBuffer :: []Color
DepthBuffer :: []f32
Vertex2DBuffer :: []Point3D
IndexBuffer :: []TriIndices
NormalBuffer :: []Vec3

FaceVertex :: struct {
	vertex_index:  i32,
	texture_index: i32,
	normal_index:  i32,
}

MeshFace :: struct {
	vertex_info: []FaceVertex,
}

Mesh :: struct {
	vertices:           []Point3D,
	normals:            []Vec3,
	tri_vertex_indices: []TriIndices,
	tri_normal_indices: []TriIndices,
	faces:              []MeshFace,
	tex_coords:         []Vec2,
}

Texture :: struct {
	buffer: []Color,
}

Model :: struct {
	mesh:            ^Mesh,
	texture:         []Color,
	transform:       Transform,
	debug_tricolors: []Color,
}

ModelTransform :: struct {
	model:     ^Model,
	transform: Transform,
}

CameraProjection :: enum {
	Perspective,
	Orthographic,
}

Camera :: struct {
	position:   Vec3,
	target:     Vec3,
	up:         Vec3,
	fov:        f32,
	projection: CameraProjection,
}

LightType :: enum {
	Directional,
	Spot,
	Point,
	Ambient,
}

Light :: struct {
	type:       LightType,
	intensity:  f32,
	cone_angle: f32,
	range:      f32,
}

RasterizerDirectionalLight :: struct {
	transform: Transform,
	intensity: f32,
}

RasterizerSpotLight :: struct {
	transform:  Transform,
	cone_angle: f32,
	range:      f32,
	intensity:  f32,
}

RasterizerPointLight :: struct {
	position:  Point3D,
	range:     f32,
	intensity: f32,
}

TargetModelStoreInfo :: struct {
	eid:                 u32,
	vertex_offset:       u32,
	vertex_count:        u32,
	normal_offset:       u32,
	normal_count:        u32,
	vertex_index_offset: u32,
	vertex_index_count:  u32,
	normal_index_offset: u32,
	normal_index_count:  u32,
}

RasterizerTarget :: struct {
	camera:                   Camera,
	pixel_buffer:             ScreenBuffer,
	depth_buffer:             DepthBuffer,
	vertex_buffer:            Vertex2DBuffer,
	normal_buffer:            NormalBuffer,
	vertex_index_buffer:      IndexBuffer,
	normal_index_buffer:      IndexBuffer,
	directional_light_buffer: []RasterizerDirectionalLight,
	spot_light_buffer:        []RasterizerSpotLight,
	point_light_buffer:       []RasterizerPointLight,
	model_info:               []TargetModelStoreInfo,
	ambient_level:            f32,
	texture:                  rl.Texture2D,
	width:                    i32,
	height:                   i32,
}


ObjFileState :: enum {
	None,
	Vertex,
	Normal,
	TexCoord,
	Face,
}

ObjFaceElemState :: enum {
	None,
	VertInd,
	TexInd,
	NormInd,
}
mesh_load_from_file :: proc(filename: string) -> Mesh {
	_, ext := os.split_filename(filename)
	assert(ext == "obj", "[FATAL] This rasterizer only supports loading meshes from OBJ files.")
	file, open_err := os.open(filename)
	assert(open_err == io.Error.None, "[FATAL] Could not open OBJ file.")

	data, read_err := os.read_entire_file(file, runtime.default_allocator())
	assert(read_err == io.Error.None, "[FATAL] Could not read OBJ file.")

	vertices := make([dynamic]Point3D)
	normals := make([dynamic]Vec3)
	tri_vertex_indices := make([dynamic]TriIndices)
	tri_normal_indices := make([dynamic]TriIndices)
	tex_coords := make([dynamic]Vec2)
	faces := make([dynamic]MeshFace)
	lines := strings.split_lines(string(data))


	for &line in lines {
		line = strings.trim_space(line)

		if len(line) == 0 || line[0] == '#' {
			continue
		}

		fields := strings.fields(line)
		if len(fields) == 0 {
			continue
		}

		switch fields[0] {
		case "v":
			parse_vertex(fields, &vertices)

		case "vn":
			parse_normal(fields, &normals)

		case "vt":
			parse_tex_coord(fields, &tex_coords)

		case "f":
			parse_face(fields, &faces)

		// Ignore unsupported OBJ directives.
		case "s", "g", "o", "usemtl", "mtllib":
			continue

		case:
			continue
		}
	}
	for fi in 0 ..< len(faces) {
		face := &faces[fi]
		assert(len(face.vertex_info) > 2)
		for i := 1; i < len(face.vertex_info) - 1; i += 1 {
			append(
				&tri_vertex_indices,
				TriIndices {
					face.vertex_info[0].vertex_index,
					face.vertex_info[i].vertex_index,
					face.vertex_info[i + 1].vertex_index,
				},
			)
			append(
				&tri_normal_indices,
				[3]i32 {
					face.vertex_info[0].normal_index,
					face.vertex_info[i].normal_index,
					face.vertex_info[i + 1].normal_index,
				},
			)
		}
	}


	return Mesh {
		vertices = vertices[:],
		normals = normals[:],
		tri_vertex_indices = tri_vertex_indices[:],
		tri_normal_indices = tri_normal_indices[:],
		tex_coords = tex_coords[:],
		faces = faces[:],
	}
}


parse_vertex :: proc(fields: []string, points: ^[dynamic]Point3D) {
	assert(len(fields) >= 4, "Invalid OBJ vertex")

	p := Point3D{parse_f32(fields[1]), parse_f32(fields[2]), parse_f32(fields[3])}

	append(points, p)
}


parse_normal :: proc(fields: []string, normals: ^[dynamic]Vec3) {
	assert(len(fields) >= 4, "Invalid OBJ normal")

	n := Vec3{parse_f32(fields[1]), parse_f32(fields[2]), parse_f32(fields[3])}

	append(normals, n)
}


parse_tex_coord :: proc(fields: []string, tex_coords: ^[dynamic]Vec2) {
	assert(len(fields) >= 3, "Invalid OBJ texture coordinate")

	uv := Vec2{parse_f32(fields[1]), parse_f32(fields[2])}

	append(tex_coords, uv)
}


parse_face :: proc(fields: []string, faces: ^[dynamic]MeshFace) {
	assert(len(fields) >= 4, "OBJ face must contain at least 3 vertices")

	vertex_indices := make([dynamic]i32)
	texture_indices := make([dynamic]i32)
	face_vertices := make([dynamic]FaceVertex)

	normal_index: i32 = -1

	for elem in fields[1:] {
		face_vertex: FaceVertex
		face_vertex.vertex_index, face_vertex.texture_index, face_vertex.normal_index =
			parse_face_element(elem)
		append(&face_vertices, face_vertex)
	}
	append(faces, MeshFace{vertex_info = face_vertices[:]})
}


// Parses:
//
//   12
//   12/3
//   12//7
//   12/3/7
//
// OBJ indices are 1-based, so they are converted to 0-based here.
parse_face_element :: proc(
	elem: string,
) -> (
	vertex_index: i32,
	texture_index: i32,
	normal_index: i32,
) {
	vertex_index = -1
	texture_index = -1
	normal_index = -1

	parts := strings.split(elem, "/")

	assert(len(parts) >= 1 && len(parts) <= 3, "Invalid OBJ face element")

	if len(parts[0]) > 0 {
		vertex_index = parse_obj_index(parts[0])
	}

	if len(parts) >= 2 && len(parts[1]) > 0 {
		texture_index = parse_obj_index(parts[1])
	}

	if len(parts) >= 3 && len(parts[2]) > 0 {
		normal_index = parse_obj_index(parts[2])
	}

	return
}


parse_obj_index :: proc(s: string) -> i32 {
	value, ok := strconv.parse_int(s)
	assert(ok, "Invalid OBJ index")

	// OBJ indices are 1-based.
	assert(value > 0, "Negative/relative OBJ indices are not supported")

	return i32(value) - 1
}

parse_f32 :: proc(s: string) -> f32 {
	value, ok := strconv.parse_f32(s)
	assert(ok, "Invalid OBJ floating-point value")
	return value
}

mesh_create_from_rect3d :: proc(rect: Rect3D) -> Mesh {
	mesh := Mesh{}
	mesh.vertices = make([]Point3D, 4)
	mesh.vertices[0] = rect.x1
	mesh.vertices[1] = rect.x2
	mesh.vertices[2] = rect.y2
	mesh.vertices[3] = rect.y1
	mesh.tri_vertex_indices = make([]TriIndices, 2)
	mesh.tri_vertex_indices[0] = {0, 1, 2}
	mesh.tri_vertex_indices[1] = {0, 2, 3}

	return mesh
}

model_create_from_mesh :: proc(mesh: ^Mesh, transform: Transform = UNIT_TRANSFORM) -> Model {
	tricolors := make([]Color, len(mesh.tri_vertex_indices))

	for &color in tricolors do color = generate_random_color()
	return Model{mesh = mesh, debug_tricolors = tricolors, transform = transform}
}


point3d_local_to_point3d_world :: proc(p: Point3D, transform: Transform) -> Point3D {
	return(
		vec3_rotate_by_quaternion(p, transform.rotation) * transform.scale +
		transform.translation \
	)
}

point3d_world_to_point3d_local :: proc(p: Point3D, transform: Transform) -> Point3D {
	return(
		-transform.translation +
		vec3_rotate_by_quaternion(p, quaternion_inverse(transform.rotation)) / transform.scale \
	)
}

point3d_world_to_point3d_view :: proc(p: Point3D, camera: Camera) -> Point3D {
	forward := vec_normalize(camera.position - camera.target)
	right := vec_normalize(vec3_cross(forward, camera.up))
	up := vec3_cross(right, forward)

	relative := p - camera.position

	return {vec_dot(relative, right), vec_dot(relative, up), vec_dot(relative, -forward)}
}

point3d_world_to_point2d_target :: proc(
	p_world: Point3D,
	target_width: i32,
	target_height: i32,
	camera: Camera,
) -> (
	point2d: Point2D,
	depth: f32,
) {
	p_view := point3d_world_to_point3d_view(p_world, camera)
	screen_height_world: f32 = math.tan(camera.fov / 2) * 2
	pixels_per_world_unit :=
		f32(target_height) /
		screen_height_world /
		(camera.projection == .Perspective ? p_view.z : 1)
	pixel_offset := p_view.xy * pixels_per_world_unit
	return pixel_offset + {f32(target_width), f32(target_height)} / 2, p_view.z
}

triangle3d_to_triangle2d_depths :: proc(tri3d: Triangle3D) -> (tri2d: Triangle2D, depths: Vec3) {
	return {tri3d[0].xy, tri3d[1].xy, tri3d[2].xy}, {tri3d[0].z, tri3d[1].z, tri3d[2].z}
}

rasterizer_render_scene :: proc(
	target: ^RasterizerTarget,
	arena: ^MemoryArena,
	models: []Maybe(^Model),
	transforms: []Transform,
	lights: []Maybe(Light),
	count: i32,
	wireframe: b32 = false,
) {

	total_vertex_count: int
	total_normal_count: int
	total_vertex_index_count: int
	total_normal_index_count: int
	total_directional_light_count: int
	total_point_light_count: int
	total_spot_light_count: int

	for m_i in 0 ..< count {
		model, has_model := models[m_i].(^Model)
		if has_model {
			total_vertex_count += len(model.mesh.vertices)
			total_normal_count += len(model.mesh.normals)
			total_vertex_index_count += len(model.mesh.tri_vertex_indices)
			total_normal_index_count += len(model.mesh.tri_normal_indices)
		}
	}

	for l_i in 0 ..< count {
		light, has_light := lights[l_i].(Light)
		if has_light {
			#partial switch light.type {
			case .Directional:
				{
					total_directional_light_count += 1
				}
			case .Point:
				{
					total_point_light_count += 1
				}
			case .Spot:
				{
					total_spot_light_count += 1
				}
			}
		}
	}

	target.vertex_buffer = arena_make(arena, Vertex2DBuffer, total_vertex_count)
	target.normal_buffer = arena_make(arena, NormalBuffer, total_normal_count)
	target.vertex_index_buffer = arena_make(arena, []TriIndices, total_vertex_index_count)
	target.normal_index_buffer = arena_make(arena, []TriIndices, total_normal_index_count)
	target.directional_light_buffer = arena_make(
		arena,
		[]RasterizerDirectionalLight,
		total_directional_light_count,
	)
	target.point_light_buffer = arena_make(arena, []RasterizerPointLight, total_point_light_count)
	target.spot_light_buffer = arena_make(arena, []RasterizerSpotLight, total_spot_light_count)

	// if total_vertex_count > len(target.vertex_buffer) do resize(&target.vertex_buffer, total_vertex_count)
	// if total_normal_count > len(target.normal_buffer) do resize(&target.normal_buffer, total_normal_count)
	// if total_vertex_index_count > len(target.vertex_index_buffer) do resize(&target.vertex_index_buffer, total_vertex_index_count)
	// if total_normal_index_count > len(target.normal_index_buffer) do resize(&target.normal_index_buffer, total_normal_index_count)

	tdl_i, tpl_i, tsl_i, tv_i, tvi_i, tn_i, tni_i: i32

	for l_i in 0 ..< count {
		light, has_light := lights[l_i].(Light)
		if has_light {
			switch light.type {
			case .Ambient:
				target.ambient_level += light.intensity
			case .Directional:
				{
					target.directional_light_buffer[tdl_i] = RasterizerDirectionalLight {
						transform = transforms[l_i],
						intensity = light.intensity,
					}

					tdl_i += 1
				}
			case .Point:
				{
					target.point_light_buffer[tpl_i] = RasterizerPointLight {
						position  = transforms[l_i].translation,
						intensity = light.intensity,
					}
					tpl_i += 1
				}
			case .Spot:
				{
					target.spot_light_buffer[tsl_i] = RasterizerSpotLight {
						transform  = transforms[l_i],
						intensity  = light.intensity,
						cone_angle = light.cone_angle,
						range      = light.range,
					}
					tsl_i += 1
				}
			}
		}
	}

	for m_i in 0 ..< count {
		model, has_model := models[m_i].(^Model)
		if has_model {
			vertex_offset := tv_i
			normal_offset := tn_i
			assert(
				len(model.mesh.tri_normal_indices) == len(model.mesh.tri_vertex_indices),
				"[FATAL] Model must have same number of tri faces and normals",
			)

			combined_transform := transform_add(transforms[m_i], model.transform)
			for vertex in model.mesh.vertices {
				target.vertex_buffer[tv_i] = point3d_local_to_point3d_world(
					vertex,
					combined_transform,
				)
				tv_i += 1
			}

			for normal in model.mesh.normals {
				target.normal_buffer[tn_i] = vec3_rotate_by_quaternion(
					normal,
					combined_transform.rotation,
				)
				tn_i += 1
			}

			for norm_inds in model.mesh.tri_normal_indices {
				target.normal_index_buffer[tni_i] = norm_inds + normal_offset
				tni_i += 1
			}

			for tri in model.mesh.tri_vertex_indices {
				target.vertex_index_buffer[tvi_i] = tri + vertex_offset
				tvi_i += 1
			}
		}
	}
	assert(tni_i == tvi_i, "[FATAL] Scene must have same number of tri faces and normal sets")
	for i in 0 ..< tvi_i {
		tri_inds := target.vertex_index_buffer[i]
		normal_inds := target.normal_index_buffer[i]

		tri3d := Triangle3D {
			target.vertex_buffer[tri_inds[0]],
			target.vertex_buffer[tri_inds[1]],
			target.vertex_buffer[tri_inds[2]],
		}

		normals := [3]Vec3 {
			target.normal_buffer[normal_inds[0]],
			target.normal_buffer[normal_inds[1]],
			target.normal_buffer[normal_inds[2]],
		}

		avg_normal := (normals[0] + normals[1] + normals[2]) / 3

		tri2d: Triangle2D
		depths: Vec3
		for i in 0 ..< 3 do tri2d[i], depths[i] = point3d_world_to_point2d_target(tri3d[i], target.width, target.height, target.camera)

		if depths[0] <= 0 || depths[1] <= 0 || depths[2] <= 0 do continue
		tri2d_bb := triangle2d_get_bounding_box(tri2d, f32(target.width), f32(target.height))

		light_intensity: Vec3 = target.ambient_level
		face_position := (tri3d.x + tri3d.y + tri3d.z) / 3
		for pl_i in 0 ..< total_point_light_count {
			light := target.point_light_buffer[pl_i]

			light_direction := light.position - face_position
			light_distance := vec_length(light_direction)
			light_direction_norm := vec_normalize(light_direction)
			light_intensity += vec3_max(
				0,
				vec3_splat_dot(normals, light_direction_norm) / light_distance * light.intensity,
			)
		}

		for dl_i in 0 ..< total_directional_light_count {
			light := target.directional_light_buffer[dl_i]

			light_direction := vec3_rotate_by_quaternion({1, 0, 0}, light.transform.rotation)
			light_intensity += vec3_max(
				0,
				vec3_splat_dot(normals, light_direction) * light.intensity,
			)
		}

		for sl_i in 0 ..< total_spot_light_count {
			light := target.spot_light_buffer[sl_i]

			light_forward := vec_normalize(
				vec3_rotate_by_quaternion({1, 0, 0}, light.transform.rotation),
			)

			light_to_face := face_position - light.transform.translation
			distance := vec_length(light_to_face)

			if distance <= 0 do continue
			if distance > light.range do continue

			light_to_face_direction := light_to_face / distance
			cone_cosine := math.cos(light.cone_angle * 0.5)
			if vec_dot(light_forward, light_to_face_direction) < cone_cosine {
				continue
			}

			face_to_light_direction := -light_to_face_direction
			n_dot_l := vec3_max(vec3_splat_dot(normals, face_to_light_direction), 0)
			light_intensity += vec3_max(0, n_dot_l * light.intensity / distance)
		}

		for neg_y in i32(tri2d_bb.y1) ..< i32(tri2d_bb.y2) {
			y := i32(target.height) - neg_y - 1
			assert(y >= 0 && y < target.height)
			for x in i32(tri2d_bb.x1) ..< i32(tri2d_bb.x2) {
				assert(x >= 0 && x < target.width)
				in_tri, weights := point2d_in_triangle2d({f32(x), f32(neg_y)}, tri2d)
				pixel_index := y * target.width + x
				if in_tri {
					if wireframe {
						if point2d_on_triangle2d({f32(x), f32(neg_y)}, tri2d) {
							target.pixel_buffer[pixel_index] = DEBUG_COLOR
						}
					} else {
						depth := 1 / vec_dot(1 / depths, weights) // NOTE: account for perspective foreshortening
						if (depth <= target.depth_buffer[pixel_index]) {
							bary_tri := barycentric({f32(x), f32(neg_y)}, tri2d)
							corrected_weights := weights / depths * depth
							normal := vec_normalize(
								vec_sum(vec_splat_mul(normals, corrected_weights)),
							)
							pixel_light_intensity := vec3_sum(light_intensity * corrected_weights)
							target.pixel_buffer[pixel_index] = color_from_intensity(
								pixel_light_intensity,
							)
							target.depth_buffer[pixel_index] = depth
						}
					}
				}
			}
		}
	}
}

rasterizer_scale_mesh :: proc(mesh: ^Mesh, scale: f32) {
	for &point in mesh.vertices {
		point *= scale
	}
}

rasterizer_create_render_target :: proc(width, height: i32, camera: Camera) -> RasterizerTarget {
	texture := rl.LoadTextureFromImage(rl.GenImageColor(width, height, rl.BLACK))
	pixel_buffer := make(ScreenBuffer, width * height)
	depth_buffer := make(DepthBuffer, width * height)
	model_info := make([dynamic]TargetModelStoreInfo, 0, 1024)

	return RasterizerTarget {
		width        = width,
		height       = height,
		texture      = texture,
		pixel_buffer = pixel_buffer,
		depth_buffer = depth_buffer,
		//model_info = model_info,
		camera       = camera,
	}
}

rasterizer_start_frame :: proc(target: RasterizerTarget) {
	for &depth in target.depth_buffer {
		depth = math.F32_MAX
	}
}

rasterizer_clear_pixel_buffer :: proc(target: RasterizerTarget, color: Color) {
	for &pixel in target.pixel_buffer {
		pixel = color
	}
}

rasterizer_draw_frame :: proc(
	target: RasterizerTarget,
	arena: MemoryArena,
	debug_info: ^DebugInfo = nil,
	debug_overlay: b32 = false,
	enabled_metrics: [$N]DebugMetricType,
	tick: i32,
) {
	rl.UpdateTexture(target.texture, raw_data(target.pixel_buffer))
	DEBUG_log_checkpoint(debug_info, .Blit, arena, tick)
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	rl.DrawTexturePro(
		target.texture,
		{0, 0, f32(target.width), f32(target.height)},
		{0, 0, f32(target.width) * PIXEL_SIZE, f32(target.height) * PIXEL_SIZE},
		0,
		0,
		rl.WHITE,
	)

	DEBUG_log_checkpoint(debug_info, .Draw, arena, tick)

	if debug_overlay {
		assert(
			debug_info != nil,
			"[FATAL] Must provide debug_info struct when rendering debug overlay",
		)
		DEBUG_display_overlay(debug_info, enabled_metrics)
	}
	rl.EndDrawing()
	rasterizer_clear_pixel_buffer(target, BLACK)
}
