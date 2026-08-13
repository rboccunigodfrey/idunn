package idunn

import "core:math"

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Vec :: union {
	Vec2,
	Vec3,
	Vec4,
}

Mat4x4 :: matrix[4, 4]f32
Mat3x3 :: matrix[3, 3]f32
Mat2x2 :: matrix[2, 2]f32

TriIndices :: [3]i32
Point2D :: Vec2
Line2D :: [2]Point2D
Triangle2D :: [3]Point2D

Rect2D :: struct #raw_union {
	using _: struct {
		x1: f32,
		y1: f32,
		x2: f32,
		y2: f32,
	},
	using e: Vec4,
}

Rect3D :: struct #raw_union {
	using _: struct {
		x1: Point3D,
		y1: Point3D,
		x2: Point3D,
		y2: Point3D,
	},
	using e: [4]Point3D,
}

Point3D :: Vec3
Line3D :: [2]Point3D
Triangle3D :: [3]Point3D

Angle3D :: struct #raw_union {
	using _: struct {
		pitch: f32,
		yaw:   f32,
		roll:  f32,
	},
	using e: Vec3,
}

Point :: union {
	Point2D,
	Point3D,
}

Line :: union {
	Line2D,
	Line3D,
}

Triangle :: union {
	Triangle2D,
	Triangle3D,
}

Transform :: struct {
	translation: Vec3,
	scale:       Vec3,
	rotation:    quaternion128,
}

VEC2_ZERO: Vec2 : {0, 0}
VEC2_ONE: Vec2 : {1, 1}
VEC2_X: Vec2 : {1, 0}
VEC2_Y: Vec2 : {0, 1}

VEC3_UP: Vec3 : {0, 1, 0}
VEC3_FORWARD: Vec3 : {0, 0, 1}
VEC3_ZERO: Vec3 : {0, 0, 0}
VEC3_ONE: Vec3 : {1, 1, 1}
VEC3_X: Vec3 : {1, 0, 0}
VEC3_Y: Vec3 : {0, 1, 0}
VEC3_Z: Vec3 : {0, 0, 1}
VEC3_XY: Vec3 : {1, 1, 0}
VEC3_XZ: Vec3 : {1, 0, 1}
VEC3_YZ: Vec3 : {0, 1, 1}

UNIT_QUATERNION :: quaternion(real = 1, imag = 0, jmag = 0, kmag = 0)

UNIT_TRANSFORM :: Transform {
	scale    = 1,
	rotation = UNIT_QUATERNION,
}

rect3d_elems :: proc(x1: Point3D, x2: Point3D, y1: Point3D, y2: Point3D) -> Rect3D {
	return Rect3D{e = {x1, x2, y1, y2}}
}

rect3d_vec4 :: proc(v: [4]Point3D) -> Rect3D {
	return Rect3D{e = v}
}

rect :: proc {
	rect3d_elems,
	rect3d_vec4,
}

angle3d_from_elems :: proc(yaw: f32 = 0, pitch: f32 = 0, roll: f32 = 0) -> Angle3D {
	return Angle3D{e = {pitch, yaw, roll}}
}

angle3d_from_vec3 :: proc(v: Vec3) -> Angle3D {
	return Angle3D{e = v}
}

angle :: proc {
	angle3d_from_elems,
	angle3d_from_vec3,
}

line2d_from_points :: proc(p1: Point2D, p2: Point2D) -> Line2D {
	return Line2D{p1, p2}

}

line :: proc {
	line2d_from_points,
}

transform_absolute_from_elems :: proc(
	translation: Vec3 = 0,
	scale: Vec3 = VEC3_ONE,
	rotation: quaternion128 = UNIT_QUATERNION,
) -> Transform {
	return Transform{translation = translation, rotation = rotation, scale = scale}
}

transform_relative_from_elems :: proc(
	current_transform: ^Transform,
	translation: Vec3 = 0,
	scale: Vec3 = VEC3_ONE,
	rotation: quaternion128 = UNIT_QUATERNION,
) {
	current_transform.translation += translation
	current_transform.scale *= scale
	current_transform.rotation *= rotation
}


transform_absolute_from_angle :: proc(
	translation: Vec3 = 0,
	scale: Vec3 = VEC3_ONE,
	angle: Angle3D = {},
) -> Transform {
	return Transform {
		translation = translation,
		scale = scale,
		rotation = quaternion_from_angle3d(angle),
	}
}

transform_relative_from_angle :: proc(
	current_transform: ^Transform,
	translation: Vec3 = 0,
	scale: Vec3 = VEC3_ONE,
	angle: Angle3D = {},
) {
	current_transform.translation += translation
	current_transform.scale *= scale
	current_transform.rotation *= quaternion_from_angle3d(angle)
}

combined_transform :: proc {
	transform_absolute_from_elems,
	transform_absolute_from_angle,
	transform_relative_from_elems,
	transform_relative_from_angle,
}

transform_add :: proc(first: Transform, transforms: ..Transform) -> (result: Transform) {
	result = first
	for transform in transforms {
		result.translation += transform.translation
		result.scale *= transform.scale
		result.rotation *= transform.rotation
	}

	return
}

transform_add_array :: proc(arr1: []Transform, arr2: []Transform) -> []Transform {
	assert(len(arr1) == len(arr2), "Cannot add two transform arrays of different lengths")
	result := make([]Transform, len(arr1))
	for i in 0 ..< len(arr1) {
		result[i] = transform_add(arr1[i], arr2[i])
	}

	return result
}

vec3_from_vec2 :: proc(v: Vec2, e: f32) -> Vec3 {
	return Vec3{v.x, v.y, e}
}

vec4_from_vec3 :: proc(v: Vec3, e: f32) -> Vec4 {
	return Vec4{v.x, v.y, v.z, e}
}

vec :: proc {
	vec3_from_vec2,
	vec4_from_vec3,
}

vec3_clamp :: proc(v: Vec3, min: Vec3, max: Vec3) -> Vec3 {
	return {clamp(v.x, min.x, max.x), clamp(v.y, min.y, max.y), clamp(v.z, min.z, max.z)}
}

vec_of_vec3_sum :: proc(v: [$N]Vec3) -> (result: Vec3) {
	for i in 0 ..< N do result += v[i]
	return
}

vec3_sum :: proc(v: Vec3) -> f32 {
	return v[0] + v[1] + v[2]
}

vec_sum :: proc {
	vec3_sum,
	vec_of_vec3_sum,
}

vec2_dot :: proc(v1: Vec2, v2: Vec2) -> f32 {
	return v1.x * v2.x + v1.y * v2.y
}

vec3_dot :: proc(v1: Vec3, v2: Vec3) -> f32 {
	return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
}

vec_dot :: proc {
	vec2_dot,
	vec3_dot,
}

vec3_cross :: proc(a: Vec3, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}}


vec3_splat_mul :: proc(arr: [$N]Vec3, v: Vec3) -> (result: [N]Vec3) {
	for i in 0 ..< N do result[i] = arr[i] * v
	return
}

vec3_splat_dot :: proc(arr: [$N]Vec3, v: Vec3) -> (result: Vec3) {
	for i in 0 ..< N do result[i] = vec_dot(arr[i], v)
	return
}

vec3_max :: proc(v1: Vec3, v2: Vec3) -> Vec3 {
	return {max(v1[0], v2[0]), max(v1[1], v2[1]), max(v1[2], v2[2])}
}

vec_splat_mul :: proc {
	vec3_splat_mul,
}

vec2_perpendicular :: proc(v: Vec2) -> Vec2 {
	return {v.y, -v.x}
}

vec3_perpendicular :: proc(v: Vec3) -> Vec3 {
	return vec3_cross(v, VEC3_UP)
}

vec_perpendicular :: proc {
	vec2_perpendicular,
	vec3_perpendicular,
}

vec3_abs :: proc(v: Vec3) -> Vec3 {
	return {abs(v.x), abs(v.y), abs(v.z)}
}

vec_abs :: proc {
	vec3_abs,
}

vec_length_sq :: proc(v: $T) -> f32 where T == Vec2 || T == Vec3 {
	return vec_dot(v, v)
}

vec_length :: proc(v: $T) -> f32 where T == Vec2 || T == Vec3 {
	return (math.sqrt(vec_length_sq(v)))
}

vec_normalize_with_length :: proc(v: $T, length: f32) -> T where T == Vec2 || T == Vec3 {
	if length == 0 do return 0
	return v / length
}

vec_normalize :: proc(v: $T) -> T where T == Vec2 || T == Vec3 {
	return vec_normalize_with_length(v, vec_length(v))
}

vec3_lerp :: proc(a, b: Vec3, t: f32) -> Vec3 {
	return a + (b - a) * t
}

mat3x3_from_vec3s :: proc(v1: Vec3, v2: Vec3) -> Mat3x3 {
	return {0, 0, 0, v1.x, v1.y, v1.z, v2.x, v2.y, v2.z}
}

mat3x3_from_quaternion :: proc(q: quaternion128) -> Mat3x3 {
	rx := vec3_rotate_by_quaternion(VEC3_X, q)
	ry := vec3_rotate_by_quaternion(VEC3_Y, q)
	rz := vec3_rotate_by_quaternion(VEC3_Z, q)

	// Rows are the rotated basis vectors, so R * v == rotate(v, q).
	return Mat3x3 {
		rx.x, ry.x, rz.x,
		rx.y, ry.y, rz.y,
		rx.z, ry.z, rz.z,
	}
}

quaternion_from_vec3_and_scalar_angle :: proc(axis: Vec3, angle: f32) -> quaternion128 {
	vnorm := vec_normalize(axis)
	s := math.sin(angle / 2)

	return quaternion(w = math.cos(angle / 2), x = s * vnorm.x, y = s * vnorm.y, z = s * vnorm.z)
}

quaternion_from_angle3d :: proc(v: Vec3) -> quaternion128 {
	vlen := vec_length(v)
	return quaternion_from_vec3_and_scalar_angle(v, vlen)
}

quaternion_normalize_sq :: proc(q: quaternion128) -> f32 {
	return q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z
}

quaternion_conjugate :: proc(q: quaternion128) -> quaternion128 {
	return quaternion(w = q.w, x = -q.x, y = -q.y, z = -q.z)
}

quaternion_inverse :: proc(q: quaternion128) -> quaternion128 {
	conj := quaternion_conjugate(q)
	norm_sq := quaternion_normalize_sq(q)
	return quaternion(
		w = conj.w / norm_sq,
		x = conj.x / norm_sq,
		y = conj.y / norm_sq,
		z = conj.z / norm_sq,
	)
}
quaternion_lerp :: proc(a, b: quaternion128, t: f32) -> quaternion128 {
	t := clamp(t, 0, 1)

	// q and -q represent the same rotation.
	// Flip b if necessary so interpolation takes the shorter path.
	dot := a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w

	target := b

	if dot < 0 {
		target = quaternion(x = -b.x, y = -b.y, z = -b.z, w = -b.w)
	}

	result := quaternion(
		x = a.x + (target.x - a.x) * t,
		y = a.y + (target.y - a.y) * t,
		z = a.z + (target.z - a.z) * t,
		w = a.w + (target.w - a.w) * t,
	)

	length := math.sqrt(
		result.x * result.x + result.y * result.y + result.z * result.z + result.w * result.w,
	)

	return quaternion(
		x = result.x / length,
		y = result.y / length,
		z = result.z / length,
		w = result.w / length,
	)
}

vec3_from_quaternion :: proc(q: quaternion128) -> Vec3 {
	return {q.x, q.y, q.z}
}

quaternion_from_basis_vec3 :: proc(v: Vec3) -> quaternion128 {
	return quaternion(real = 0, imag = v.x, jmag = v.y, kmag = v.z)
}

vec3_rotate_by_quaternion :: proc(v: Vec3, q: quaternion128) -> Vec3 {
	vec_q := quaternion_from_basis_vec3(v)
	q_conj := quaternion_inverse(q)
	rot_vec_q := q * vec_q * q_conj
	return vec3_from_quaternion(rot_vec_q)
}


triangle2d_get_sides :: proc(tri: Triangle2D) -> [3]Line2D {
	return {tri.xy, tri.yz, tri.zx}
}

triangle2d_area :: proc(tri: Triangle2D) -> f32 {
	return point2d_line2d_get_signed_area(tri[0], {tri[1], tri[2]})
}

triangle2d_get_bounding_box :: proc(
	tri: Triangle2D,
	max_width: f32,
	max_height: f32,
) -> (
	result: Rect2D,
) {
	min_x := min(tri[0].x, tri[1].x, tri[2].x)
	min_y := min(tri[0].y, tri[1].y, tri[2].y)
	max_x := max(tri[0].x, tri[1].x, tri[2].x)
	max_y := max(tri[0].y, tri[1].y, tri[2].y)

	result.x1 = clamp(math.floor(min_x), 0, max_width)
	result.y1 = clamp(math.floor(min_y), 0, max_height)
	result.x2 = clamp(math.ceil(max_x), 0, max_width)
	result.y2 = clamp(math.ceil(max_y), 0, max_height)

	return
}

point2d_line2d_get_signed_area :: proc(p: Point2D, l: Line2D) -> f32 {
	ap := p - l[0]
	ab_perp := vec_perpendicular(l[1] - l[0])

	return vec_dot(ap, ab_perp) * 0.5
}

point2d_on_line2d :: proc(p: Point2D, l: Line2D) -> b32 {
	e: f32 = 0.5
	dist := math.abs((l[1].x - l[0].x) * (p.y - l[0].y) - (l[1].y - l[0].y) * (p.x - l[0].x))
	return dist > -e && dist < e
}

point2d_in_triangle2d :: proc(p: Point2D, tri: Triangle2D) -> (in_tri: b32, weights: Vec3) {
	sides := triangle2d_get_sides(tri)
	areaABP := point2d_line2d_get_signed_area(p, sides[0])
	areaBCP := point2d_line2d_get_signed_area(p, sides[1])
	areaCAP := point2d_line2d_get_signed_area(p, sides[2])

	total_area := (areaABP + areaBCP + areaCAP)
	in_tri = areaABP >= 0 && areaBCP >= 0 && areaCAP >= 0 && total_area > 0
	inv_area_sum := 1 / total_area
	weights = {areaBCP, areaCAP, areaABP} * inv_area_sum

	return
}

point2d_on_triangle2d :: proc(p: Point2D, tri: Triangle2D) -> b32 {
	sides := triangle2d_get_sides(tri)
	return(
		point2d_on_line2d(p, sides[0]) ||
		point2d_on_line2d(p, sides[1]) ||
		point2d_on_line2d(p, sides[2]) \
	)
}

atan2_fast :: proc(y: f32, x: f32) -> (result: f32) {
	angle := min(abs(x), abs(y)) / max(abs(x), abs(y))
	angle_sq := angle * angle
	result =
		((-0.0464964749 * angle_sq + 0.15931422) * angle_sq - 0.327622764) * angle_sq * angle +
		angle
	if abs(y) > abs(x) do result = 1.57079637 - result
	if x < 0 do result = 3.14159274 - result
	if y < 0 do result = -result

	return
}

barycentric :: proc(p2d: Point2D, tri2d: Triangle2D) -> Vec3 {
	tri_area := triangle2d_area(tri2d)

	sides := triangle2d_get_sides(tri2d)
	return {
		point2d_line2d_get_signed_area(p2d, sides[0]) / tri_area,
		point2d_line2d_get_signed_area(p2d, sides[1]) / tri_area,
		point2d_line2d_get_signed_area(p2d, sides[2]) / tri_area,
	}
}
