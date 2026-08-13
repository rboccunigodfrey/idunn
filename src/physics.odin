package idunn

import "core:math"

MAX_QUEUE_SIZE :: 256

RigidBodyType :: enum {
	Static,
	Kinematic,
	Dynamic,
}

PhysicsQueueFunction :: proc(
	rb: ^RigidBody,
	args: PhysicsQueueArgSet,
	dt: f32,
) -> (
	result: PhysicsQueueItem,
	found: b32,
)

PhysicsQueueItemType :: enum {
	AddForce,
	ApplyImpulse,
}

AddForceArgs :: struct {
	force:    Vec3,
	duration: f32,
}

ApplyImpulseArgs :: struct {
	impulse:  Vec3,
	duration: f32,
}

PhysicsQueueArgSet :: union {
	AddForceArgs,
	ApplyImpulseArgs,
}

PhysicsQueueItem :: struct {
	type:     PhysicsQueueItemType,
	rb:       ^RigidBody,
	arg_set:  PhysicsQueueArgSet,
	function: PhysicsQueueFunction,
}

PhysicsSolverQueue :: struct {
	queue:       [MAX_QUEUE_SIZE]PhysicsQueueItem,
	starting_at: i32,
	size:        i32,
}

physics_update_queue :: proc(queue: ^PhysicsSolverQueue, dt: f32) {
	starting_at := queue.starting_at
	size := queue.size
	new_queue_count: i32
	for i in 0 ..< size {
		queue_index := (starting_at + i)
		queue_item := queue.queue[queue_index]

		next_queue_item, has_next_queue_item := physics_queue_function_caller(
			queue,
			queue_item.type,
			queue_item.rb,
			queue_item.arg_set,
			dt,
			queue_item.function,
		)

		queue.starting_at = (queue.starting_at + 1) % MAX_QUEUE_SIZE
		queue.size -= 1
		if has_next_queue_item {
			queue.queue[(starting_at + size + new_queue_count) % MAX_QUEUE_SIZE] = next_queue_item
			new_queue_count += 1

		}
	}
	queue.size += new_queue_count
}

physics_queue_function_caller :: proc(
	queue: ^PhysicsSolverQueue,
	type: PhysicsQueueItemType,
	rb: ^RigidBody,
	args: PhysicsQueueArgSet,
	dt: f32,
	function: PhysicsQueueFunction,
) -> (
	result: PhysicsQueueItem,
	found: b32,
) {
	switch type {
	case .AddForce:
		result, found = function(rb, args.(AddForceArgs), dt)
	case .ApplyImpulse:
		result, found = function(rb, args.(ApplyImpulseArgs), dt)
	}

	return
}

RigidBody :: struct {
	type:               RigidBodyType,
	previous_transform: Transform,
	transform:          Transform,
	velocity:           Vec3,
	force:              Vec3,
	mass:               f32,
	floored:            b32,
}

rigidbody :: proc(
	type: RigidBodyType,
	transform: Transform = UNIT_TRANSFORM,
	mass: f32 = 1,
) -> RigidBody {
	return RigidBody{type = type, transform = transform, mass = mass}
}

ColliderShape :: enum {
	Ball,
	Cuboid,
	Cylinder,
}

Collider :: struct {
	shape:     ColliderShape,
	transform: Transform,
}

RIGIDBODY_STATIC :: RigidBody {
	type      = .Static,
	transform = UNIT_TRANSFORM,
	mass      = 1,
}

RIGIDBODY_KINETIC :: RigidBody {
	type      = .Kinematic,
	transform = UNIT_TRANSFORM,
	mass      = 1,
}

RIGIDBODY_DYNAMIC :: RigidBody {
	type      = .Dynamic,
	transform = UNIT_TRANSFORM,
	mass      = 1,
}

momentum_fn :: proc(velocity: Vec3, mass: f32) -> Vec3 {
	return velocity * mass
}

acceleration_fn :: proc(force: Vec3, mass: f32) -> Vec3 {
	return force / mass
}

volume_fn :: proc(radius: f32) -> f32 {
	return 4 * 0.33 * math.PI * radius * radius * radius
}

mass_fn :: proc(density: f32, radius: f32) -> f32 {
	return density * volume_fn(radius)
}

gravity_force_fn :: proc(mass: f32) -> Vec3 {
	return mass * GRAVITY
}

quadratic_drag_force_fn :: proc(mass: f32, velocity: Vec3, coefficient: f32) -> Vec3 {
	speed_sq := vec_length_sq(velocity)
	if speed_sq <= 0.00001 {
		return {}
	}
	speed := math.sqrt(speed_sq)
	return -velocity * speed * mass * coefficient
}

normal_force_fn :: proc(mass: f32, incline_angle: f32) -> Vec3 {
	return mass * math.cos(incline_angle) * GRAVITY
}

normal_force_magnitude_fn :: proc(gravity_force: Vec3, normal: Vec3) -> f32 {
	return max(-vec3_dot(gravity_force, normal), 0)
}

kinetic_friction_force_fn :: proc(
	relative_velocity: Vec3,
	contact_normal: Vec3,
	normal_force_magnitude: f32,
	coefficient: f32,
) -> Vec3 {
	n := vec_normalize(contact_normal)

	normal_velocity := n * vec3_dot(relative_velocity, n)
	tangent_velocity := relative_velocity - normal_velocity

	tangent_speed := vec_length(tangent_velocity)

	if (tangent_speed <= 0.0001) {
		return {}
	}

	friction_direction := -tangent_velocity / tangent_speed
	friction_magnitude := coefficient * normal_force_magnitude

	return friction_direction * friction_magnitude
}

convert_args :: proc(args: PhysicsQueueArgSet, $T: typeid, dt: f32 = -1) -> T {
	result, ok := args.(T)
	assert(ok, "[FATAL] Invalid arg conversion")
	when T == AddForceArgs || T == ApplyImpulseArgs {
		assert(
			args.(T).duration != 0 || dt == -1,
			"[FATAL] Attempted to set set a duration without setting dt",
		)

	}

	return result
}

impulse :: proc(impulse: Vec3, duration: f32 = 0) -> (result: ApplyImpulseArgs) {
	result.impulse = impulse
	result.duration = duration
	return
}

physics_apply_impulse :: proc(
	rb: ^RigidBody,
	args: PhysicsQueueArgSet,
	dt: f32 = -1,
) -> (
	result: PhysicsQueueItem,
	add_to_queue: b32,
) {
	args := convert_args(args, ApplyImpulseArgs, dt)
	rb.velocity += args.impulse

	args.duration -= dt
	if args.duration > 0 {
		return PhysicsQueueItem{.ApplyImpulse, rb, args, physics_apply_impulse}, true
	}
	return
}

force :: proc(force: Vec3, duration: f32 = 0) -> (result: AddForceArgs) {
	result.force = force
	result.duration = duration
	return
}

physics_add_force :: proc(
	rb: ^RigidBody,
	args: PhysicsQueueArgSet,
	dt: f32 = -1,
) -> (
	result: PhysicsQueueItem,
	add_to_queue: b32,
) {
	args := convert_args(args, AddForceArgs)
	rb.force += args.force

	args.duration -= dt
	if args.duration > 0 {
		return PhysicsQueueItem{.AddForce, rb, args, physics_add_force}, true
	}
	return
}

physics_update :: proc(rb: ^RigidBody, dt: f32) {
	rb.previous_transform = rb.transform
	rb.floored = rb.transform.translation.y <= 0
	assert(rb.mass > 0)
	gravity_force := gravity_force_fn(rb.mass)
	physics_add_force(rb, force(gravity_force))


	if rb.floored {
		floor_normal := Vec3{0, 1, 0}
		normal_force_magnitude := normal_force_magnitude_fn(gravity_force, floor_normal)
		physics_add_force(
			rb,
			force(
				kinetic_friction_force_fn(
					rb.velocity,
					floor_normal,
					normal_force_magnitude,
					0.9999,
				),
			),
			dt,
		)

	} else do physics_add_force(rb, force(quadratic_drag_force_fn(rb.mass, rb.velocity, 0.5)))
	rb.velocity += acceleration_fn(rb.force, rb.mass) * dt
	MAX_VELOCITY: f32 = 2
	MIN_VELOCITY: f32 = 0.2
	vel_mag := vec_length(rb.velocity)
	if vel_mag > MAX_VELOCITY do rb.velocity = vec_normalize(rb.velocity) * MAX_VELOCITY
	if abs(rb.velocity.x) < MIN_VELOCITY do rb.velocity.x = 0
	if abs(rb.velocity.z) < MIN_VELOCITY do rb.velocity.z = 0

	rb.transform.translation += rb.velocity * dt
	rb.transform.translation = vec3_clamp(
		rb.transform.translation,
		BOUNDING_BOX * {-0.5, 0, -0.5},
		BOUNDING_BOX * {0.5, 1, 0.5},
	)
	rb.force = 0
}
