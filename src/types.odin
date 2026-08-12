package idunn

import "core:math/rand"

Color :: [4]u8

generate_random_color :: proc() -> Color {
	return {
		u8(rand.int32_range(0, 256)),
		u8(rand.int32_range(0, 256)),
		u8(rand.int32_range(0, 256)),
		255,
	}
}

color :: proc()

color_from_intensity :: proc(intensity: f32, opacity: f32 = 1.0) -> Color {
	intensity := u8(clamp(intensity, 0, 1) * 255)
	return {intensity, intensity, intensity, u8(clamp(opacity, 0, 1) * 255)}

}
