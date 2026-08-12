package idunn

import "base:runtime"
import "core:math"
import rl "vendor:raylib"

DEBUGGING: b32 : true
DEBUG_MAX_FRAME_COUNT :: 256

NUM_APPLES :: 500
DEBUG_COLOR :: Color{255, 255, 255, 50}
BOUNDING_BOX :: Vec3{10, 10, 10}
MAX_ENTITIES :: 100000


PIXEL_COUNT_X :: 240 * 1
PIXEL_COUNT_Y :: 160 * 1
PIXEL_SIZE :: 8

CameraTarget :: struct {
	offset: Vec3,
}

ComponentType :: union {
	Light,
	RigidBody,
	CameraTarget,
	Collider,
	^Model,
}

Entity :: struct {
	transform:   Transform,
	light:       Maybe(Light),
	rb:          Maybe(RigidBody),
	collider:    Maybe(Collider),
	target:      Maybe(CameraTarget),
	model:       Maybe(^Model),
	parent:      Maybe(u32),
	initialized: b32,
}

EntityStore :: struct {
	entities:    #soa[MAX_ENTITIES]Entity,
	cap:         u32,
	size:        u32,
	initialized: b32,
}

entity_store_create :: proc() -> (origin_id: u32, result: ^EntityStore) {
	result = new(EntityStore)
	result.cap = MAX_ENTITIES
	origin_id = entity_create(result)
	entity_add_components(result, origin_id, rigidbody(.Static))
	result.initialized = true
	return
}

entity_store_update :: proc(store: ^EntityStore, dt: f32) {
	for &entity in store.entities {
		if entity.initialized {
			rb, has_rb := &entity.rb.?
			if has_rb {

				if rb.type == .Dynamic do physics_update(rb, dt)

				entity.transform = rb.transform

				parent, has_parent := entity.parent.?
				if has_parent {
					parent_rb, parent_has_rb := entity_get_component(store, parent, RigidBody)
					if parent_has_rb do entity.transform = transform_add(parent_rb.transform, entity.transform)
				}
				collider, has_coll := entity.collider.?
				if has_coll do collider.transform = rb.transform
			}
		}
	}

}

entity_create :: proc(store: ^EntityStore, parent: Maybe(u32) = nil) -> u32 {
	assert(store.size < store.cap, "[FATAL] Exceeded max entity amount")
	index := store.size
	parent, not_origin := parent.?
	assert(not_origin || !store.initialized, "[FATAL] Cannot create more than one origin")
	if not_origin {
		assert(
			store.entities[parent].initialized == true,
			"[FATAL] Attempted to assign uninitialized parent",
		)
		assert(parent < store.size, "[FATAL] Attempted to assign parent out of range")
		store.entities.parent[index] = parent

	} else {
		store.entities.parent[index] = nil
	}

	store.entities[index].initialized = true
	store.size += 1
	return index
}

entity_add_components :: proc(store: ^EntityStore, eid: u32, components: ..ComponentType) {
	for comp in components {
		switch c in comp {
		case Light:
			store.entities[eid].light = comp.(Light)
		case CameraTarget:
			store.entities[eid].target = comp.(CameraTarget)
		case RigidBody:
			store.entities[eid].rb = comp.(RigidBody)
		case Collider:
			store.entities[eid].collider = comp.(Collider)
		case ^Model:
			store.entities[eid].model = comp.(^Model)
		}
	}
}

entity_get_transform :: proc(store: ^EntityStore, eid: u32) -> Transform {
	assert(eid < store.size, "[FATAL] Queried transform for invalid entity")

	return store.entities.transform[eid]
}

entity_get_component :: proc(
	store: ^EntityStore,
	eid: u32,
	$T: typeid,
) -> (
	comp: ^T,
	found: bool,
) {
	assert(eid < store.size, "[FATAL] Queried component for invalid entity")

	when T == Light do result := &store.entities[eid].light
	when T == CameraTarget do result := &store.entities[eid].target
	when T == RigidBody do result := &store.entities[eid].rb
	when T == Collider do result := &store.entities[eid].collider
	when T == ^Model do result := &store.entities[eid].model

	return &result.?
}

entity_set_component :: proc(store: ^EntityStore, eid: u32, value: $T) {
	assert(eid < store.size, "[FATAL] Queried component for invalid entity")
	comp, has_comp := entity_get_component(store, eid, typeid_of(type_of(T)))
	assert(
		has_comp,
		"[FATAL] Attempted to set component value for entity that does not contain component. Please use entity_add_components instead.",
	)
	comp = value
}

game_set_camera_target :: proc(
	store: ^EntityStore,
	target: ^RasterizerTarget,
	eid: u32,
	distance: f32 = 2,
) {
	transform := store.entities[eid].transform
	entity_target, has_target := entity_get_component(store, eid, CameraTarget)
	assert(has_target, "[FATAL] Cannot set camera target to entity with no CameraTarget component")
	current_camera_target := target.camera.target
	current_camera_position := target.camera.position

	next_camera_target := transform.translation + entity_target.offset
	next_camera_position :=
		target.camera.target +
		vec_normalize(vec3_rotate_by_quaternion(current_camera_position, transform.rotation)) *
			distance

	target.camera.target = next_camera_target
	target.camera.position = next_camera_position
}

camera_freemove :: proc(target: ^RasterizerTarget, dt: f32) {
	mouse_delta := rl.GetMouseDelta()

	scroll_sensitivity: f32 = 0.05
	orbit_sensitivity: f32 = 0.001

	current_offset := target.camera.position - target.camera.target

	yaw := mouse_delta.x * orbit_sensitivity
	pitch := -mouse_delta.y * orbit_sensitivity

	q_yaw := quaternion_from_vec3_and_scalar_angle(target.camera.up, yaw)
	offset_yawed := vec3_rotate_by_quaternion(current_offset, q_yaw)

	forward_yawed := vec_normalize(-offset_yawed)
	right := vec_normalize(vec3_cross(forward_yawed, target.camera.up))

	q_pitch := quaternion_from_vec3_and_scalar_angle(right, pitch)

	candidate_offset := vec3_rotate_by_quaternion(offset_yawed, q_pitch)
	candidate_direction := vec_normalize(candidate_offset)

	scroll := rl.GetMouseWheelMove()
	zoom := math.exp(-scroll * scroll_sensitivity)

	pole_alignment := abs(vec3_dot(candidate_direction, target.camera.up))

	rotated_offset := pole_alignment < 0.9 ? candidate_offset : offset_yawed

	rotated_offset *= zoom
	target.camera.position = target.camera.target + rotated_offset

	rl.SetMousePosition(target.width * PIXEL_SIZE / 2, target.height * PIXEL_SIZE / 2)
}

main :: proc() {

	arena := initialize_arena(runtime.Gigabyte)
	origin, entity_store := entity_store_create()
	rl.InitWindow(PIXEL_COUNT_X * PIXEL_SIZE, PIXEL_COUNT_Y * PIXEL_SIZE, "Software Rasterizer")
	defer rl.CloseWindow()
	rl.SetTargetFPS(30)
	rl.HideCursor()


	render_target := rasterizer_create_render_target(
		PIXEL_COUNT_X,
		PIXEL_COUNT_Y,
		Camera {
			position = 0.01,
			target = VEC3_ZERO,
			up = VEC3_Y,
			fov = 45,
			projection = .Perspective,
		},
	)
	monkey_mesh := mesh_load_from_file("data/models/monkeywbody.obj")
	sphere_mesh := mesh_load_from_file("data/models/ico_sphere.obj")
	cube_mesh := mesh_load_from_file("data/models/cube.obj")
	ground_mesh := mesh_load_from_file("data/models/ground.obj")
	tree_mesh := mesh_load_from_file("data/models/mushysmall.obj")
	player_mesh := mesh_load_from_file("data/models/froge.obj")

	monkey_model := model_create_from_mesh(&monkey_mesh)
	sphere_model := model_create_from_mesh(&sphere_mesh)
	cube_model := model_create_from_mesh(&cube_mesh)
	ground_model := model_create_from_mesh(&ground_mesh)
	tree_model := model_create_from_mesh(&tree_mesh, transform_absolute_from_elems(scale = 0.5))
	player_model := model_create_from_mesh(
		&player_mesh,
		transform_absolute_from_elems(translation = {0, 0.5, 0}, scale = 0.1),
	)

	render_target.ambient_level = 0.01
	scene_light := entity_create(entity_store, origin)
	entity_add_components(
		entity_store,
		scene_light,
		rigidbody(.Static),
		Light{type = .Directional, intensity = 0.1},
	)
	origin_light := entity_create(entity_store, origin)
	entity_add_components(
		entity_store,
		origin_light,
		rigidbody(.Static, transform_absolute_from_elems(translation = {0, 5.0, 6.0})),
		Light{type = .Point, intensity = 0.7},
	)

	ground := entity_create(entity_store, origin)
	entity_add_components(
		entity_store,
		ground,
		rigidbody(
			.Static,
			transform_absolute_from_elems(translation = {0, -0.1, 0}, scale = {5, 0.1, 5}),
		),
		&cube_model,
	)

	for i in 0 ..< 5 {
		tree := entity_create(entity_store, origin)
		tree_rb := rigidbody(
			.Static,
			transform_absolute_from_angle(
				translation = VEC3_X * f32((i - 2) * 2),
				angle = angle(yaw = f32(i) * 0.5),
			),
		)
		entity_add_components(entity_store, tree, tree_rb, &tree_model)
	}
	player := entity_create(entity_store, origin)
	entity_add_components(
		entity_store,
		player,
		CameraTarget{offset = {0, 0.6, 0}},
		rigidbody(.Dynamic),
		&player_model,
	)

	tick: i32 = 0
	playing := true
	camera_yaw: f32
	camera_pitch: f32 = 0.25
	camera_distance: f32 = 2
	camera_height: f32 = 0.5
	camera_follow_speed: f32 = 10
	player_rotation_speed: f32 = 10
	mouse_sensitivity: f32 = 0.001
	debug_info: DebugInfo
	debug_overlay: b32 = true


	for !rl.WindowShouldClose() {
		defer arena_clear(&arena)
		dt := rl.GetFrameTime()

		debug_info.start_time = metrics_now(tick, arena)

		rasterizer_start_frame(render_target)


		DEBUG_log_checkpoint(&debug_info, .FrameStart, arena, tick)

		if rl.GetKeyPressed() == rl.KeyboardKey.P do playing = !playing
		if rl.GetKeyPressed() == rl.KeyboardKey.O do debug_overlay = !debug_overlay

		player_rb, _ := entity_get_component(entity_store, player, RigidBody)
		player_ct, _ := entity_get_component(entity_store, player, CameraTarget)
		player_forward := vec3_rotate_by_quaternion({0, 0, 1}, player_rb.transform.rotation)
		if playing {
			movement: Vec3
			speed: f32 = 1

			if rl.IsKeyDown(rl.KeyboardKey.W) do movement.z -= 1
			if rl.IsKeyDown(rl.KeyboardKey.S) do movement.z += 1
			if rl.IsKeyDown(rl.KeyboardKey.A) do movement.x -= 1
			if rl.IsKeyDown(rl.KeyboardKey.D) do movement.x += 1

			// -----------------------------
			// Camera orbit input
			// -----------------------------

			mouse_delta := -rl.GetMouseDelta()

			camera_yaw -= mouse_delta.x * mouse_sensitivity
			//camera_pitch -= mouse_delta.y * mouse_sensitivity

			camera_pitch = clamp(camera_pitch, -1.2, 1.2)

			// -----------------------------
			// Camera target / orbit position
			// -----------------------------

			player_position := player_rb.transform.translation

			camera_target := player_position + player_ct.offset

			horizontal_distance := math.cos(camera_pitch) * camera_distance

			vertical_distance := math.sin(camera_pitch) * camera_distance

			camera_offset := Vec3 {
				math.sin(camera_yaw) * horizontal_distance,
				camera_height + vertical_distance,
				math.cos(camera_yaw) * horizontal_distance,
			}

			desired_camera_position := camera_target + camera_offset

			camera_lerp_t := 1 - math.exp(-camera_follow_speed * dt)

			render_target.camera.position = vec3_lerp(
				render_target.camera.position,
				desired_camera_position,
				camera_lerp_t,
			)

			render_target.camera.target = camera_target

			// -----------------------------
			// Camera-relative movement
			// -----------------------------

			camera_forward := render_target.camera.target - render_target.camera.position

			// Don't let camera pitch affect movement.
			camera_forward.y = 0

			if vec_length(camera_forward) > 0.000001 {
				camera_forward = vec_normalize(camera_forward)
			}

			camera_right := vec_normalize(vec3_cross({0, 1, 0}, camera_forward))

			// Because W is -Z and S is +Z.
			world_movement := camera_right * movement.x - camera_forward * movement.z

			// -----------------------------
			// Move + rotate player
			// -----------------------------

			DEBUG_log_checkpoint(&debug_info, .CameraUpdate, arena, tick)

			if vec_length(world_movement) > 0.0001 {
				world_movement = vec_normalize(world_movement)

				physics_apply_impulse(player_rb, impulse(world_movement * speed, 5.0))

				// W / A / D can rotate the character.
				// S keeps the current facing direction so the
				// player walks backward.
				desired_player_rotation := quaternion_from_vec3_and_scalar_angle(
					{0, 1, 0},
					atan2_fast(world_movement.x, world_movement.z),
				)

				player_rb.transform.rotation = quaternion_lerp(
					player_rb.transform.rotation,
					desired_player_rotation,
					1 - math.exp(-player_rotation_speed * dt),
				)
			}
			rl.SetMousePosition(
				render_target.width * PIXEL_SIZE / 2,
				render_target.height * PIXEL_SIZE / 2,
			)

		}

		DEBUG_log_checkpoint(&debug_info, .MovementUpdate, arena, tick)
		entity_store_update(entity_store, dt)

		DEBUG_log_checkpoint(&debug_info, .PhysicsUpdate, arena, tick)

		rasterizer_render_scene(
			&render_target,
			&arena,
			entity_store.entities.model[:],
			entity_store.entities.transform[:],
			entity_store.entities.light[:],
			i32(entity_store.size),
			wireframe = false,
		)

		DEBUG_log_checkpoint(&debug_info, .Render, arena, tick)

		rasterizer_draw_frame(
			render_target,
			arena,
			&debug_info,
			debug_overlay,
			[?]DebugMetricType{.TSC, .NSec, .Monotonic, .ArenaAllocations, .BytesAllocated},
			tick,
		)

		tick += 1
	}
}
